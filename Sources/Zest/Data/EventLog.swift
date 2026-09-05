import Foundation
import AppKit

// Local event feed for other tools on this Mac (the owner's health system reads it).
// Appends one JSON object per line to <eventLogDir>/zest-events.jsonl: charger plugged in
// or unplugged, fully charged, a charge cycle completing, battery temperature crossing the
// warm (35 C) and hot (40 C) bands with 2 C of hysteresis, Low Power Mode on or off, the
// system thermal pressure state changing, and Zest starting or stopping. Timestamps are
// ISO-8601 UTC. No network, no daemon: a file, written only when the user names a folder
// in Settings (config `eventLogDir`). Off by default.
final class EventLog {
    struct Event: Equatable {
        var event: String
        var fields: [String: Any] = [:]
        static func == (a: Event, b: Event) -> Bool {
            a.event == b.event && NSDictionary(dictionary: a.fields).isEqual(to: b.fields)
        }
    }

    enum TempLevel: String { case normal, warm, hot }

    static let fileName = "zest-events.jsonl"
    static let rotateAt = 1_000_000          // bytes; one previous generation is kept
    static let minInterval: TimeInterval = 60 // per event type, lifecycle exempt

    private(set) var directory: URL?
    private let host = Host.current().localizedName ?? "mac"
    private let queue = DispatchQueue(label: "com.shanky.zest.event-log", qos: .utility)
    private var lastWritten: [String: Date] = [:]
    private var previous: BatterySnapshot?
    private var tempLevel: TempLevel = .normal
    private var observers: [NSObjectProtocol] = []
    private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var thermal = ProcessInfo.processInfo.thermalState

    init(directory: String?) {
        reconfigure(directory: directory)
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            let on = ProcessInfo.processInfo.isLowPowerModeEnabled
            if on != self.lowPower { self.lowPower = on; self.append(Event(event: "low_power_mode", fields: ["on": on])) }
        })
        observers.append(nc.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            let s = ProcessInfo.processInfo.thermalState
            if s != self.thermal { self.thermal = s; self.append(Event(event: "thermal_state", fields: ["state": Self.name(s)])) }
        })
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    var isEnabled: Bool { directory != nil }

    func reconfigure(directory dir: String?) {
        guard let dir, !dir.isEmpty else { directory = nil; return }
        let url = URL(fileURLWithPath: NSString(string: dir).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directory = url
    }

    var fileURL: URL? { directory?.appendingPathComponent(Self.fileName) }

    // MARK: Battery transitions (pure, so they can be tested)

    static func events(from old: BatterySnapshot?, to new: BatterySnapshot) -> [Event] {
        guard let old else { return [] }
        var out: [Event] = []
        if old.isACPower != new.isACPower {
            out.append(Event(event: new.isACPower ? "plugged_in" : "unplugged",
                             fields: ["percent": new.percent, "adapterWatts": new.adapterWatts as Any]))
        }
        if !old.fullyCharged && new.fullyCharged {
            out.append(Event(event: "fully_charged", fields: ["percent": new.percent]))
        }
        if let a = old.cycleCount, let b = new.cycleCount, b > a {
            out.append(Event(event: "charge_cycle", fields: ["cycles": b, "maxCapacityPercent": new.maxCapacityPercent as Any]))
        }
        return out
    }

    // 35/40 C bands with 2 C hysteresis: warm enters at >= 35 and leaves below 33; hot
    // enters at >= 40 and leaves below 38. Returns the new level (same as `current` if no
    // band was crossed).
    static func tempLevel(after tempC: Double, current: TempLevel) -> TempLevel {
        switch current {
        case .normal: return tempC >= 40 ? .hot : (tempC >= 35 ? .warm : .normal)
        case .warm:   return tempC >= 40 ? .hot : (tempC < 33 ? .normal : .warm)
        case .hot:    return tempC < 38 ? (tempC < 33 ? .normal : .warm) : .hot
        }
    }

    // MARK: Sinks

    func observe(_ snap: BatterySnapshot) {
        let evts = Self.events(from: previous, to: snap)
        previous = snap
        evts.forEach { append($0) }
        if let t = snap.temperatureC {
            let level = Self.tempLevel(after: t, current: tempLevel)
            if level != tempLevel {
                tempLevel = level
                append(Event(event: "battery_temp", fields: ["level": level.rawValue, "tempC": t]))
            }
        }
    }

    func lifecycle(_ what: String) { append(Event(event: what, fields: ["version": Self.version]), rateLimited: false) }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    // MARK: Writing

    func append(_ e: Event, rateLimited: Bool = true) {
        guard let url = fileURL else { return }
        queue.async {
            let now = Date()
            if rateLimited, let last = self.lastWritten[e.event], now.timeIntervalSince(last) < Self.minInterval { return }
            self.lastWritten[e.event] = now
            var obj: [String: Any] = ["ts": TimeKeys.iso8601(now), "source": "zest", "host": self.host, "event": e.event]
            for (k, v) in e.fields where !(v is NSNull) { obj[k] = v }
            guard JSONSerialization.isValidJSONObject(obj), var data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return }
            data.append(0x0A)
            Self.rotateIfNeeded(url)
            if let h = try? FileHandle(forWritingTo: url) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: data)
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // Blocks until every queued line is on disk; used by shutdown and tests.
    func flush() { queue.sync {} }

    private static func rotateIfNeeded(_ url: URL) {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size >= rotateAt else { return }
        let old = url.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: url, to: old)
    }

    static func name(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
