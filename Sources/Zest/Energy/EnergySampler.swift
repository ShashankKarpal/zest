import Foundation
import Combine

// Per-app energy insights.
//
// Unit: CPU time per second, milliseconds per second (ms/s). From powermetrics
// (--samplers tasks) when the sudoers grant allows it, otherwise a ps %CPU proxy. Live
// shows the latest sample; the 24h/7d/30d views show the AVERAGE ms/s over whatever history
// has actually been collected. History starts only when the app is first run, so the views
// honestly report the real data span (for example, "collected over the last 3h") rather than
// implying a full week or month. Nothing is fabricated. powermetrics summary rows
// (ALL_TASKS, DEAD_TASKS) and Zest's own measurement helpers are filtered out.
final class EnergySampler: ObservableObject {
    struct AppEnergy: Identifiable, Equatable {
        var id: String { name }
        var name: String
        var value: Double         // ms/s (live: instantaneous; windows: average)
        var isMisbehaving: Bool
    }
    struct Window: Equatable {
        var live: [AppEnergy] = []
        var last24h: [AppEnergy] = []
        var last7d: [AppEnergy] = []
        var last30d: [AppEnergy] = []
        var significant: [AppEnergy] = []  // apps above the "significant energy" threshold now
        var totalLive: Double = 0          // sum of all live app ms/s (for the system grade)
        var spark24h: [Double] = []
        var spanHours: Double = 0          // how much real history exists
        var startedAt: Date? = nil         // first sample time
    }

    // Apps at or above this current draw are treated as "using significant energy", mirroring
    // the idea behind the macOS battery menu (a rolling threshold on energy impact).
    private let significantThreshold: Double = 20

    @Published private(set) var window = Window()
    @Published private(set) var usingPowermetrics = false

    private var timer: Timer?
    private let historyURL = AppConfig.dir.appendingPathComponent("energy/history.json")
    private let metaURL = AppConfig.dir.appendingPathComponent("energy/meta.json")
    private var hourly: [String: [String: Double]] = [:]   // hourKey -> app -> summed ms/s
    private var hourlyCount: [String: Int] = [:]           // hourKey -> sample count
    private var firstTS: Double = 0

    // powermetrics summary rows are totals, not processes, so they are always excluded.
    private let summaryRows: Set<String> = ["ALL_TASKS", "DEAD_TASKS"]
    // Full honesty: nothing else is hidden. The CLI tools Zest itself spawns to sample energy
    // are folded into "Zest" so its own monitoring cost is attributed to Zest rather than
    // appearing as mystery processes or being dropped.
    private let foldToZest: Set<String> = [
        "powermetrics", "top", "ioreg", "ps", "jq", "system_profiler", "ccusage", "ccusage1",
        "ccusage2", "arp", "sysctl", "vm_stat", "pmset", "memory_pressure", "pagesize", "df",
        "plutil", "scutil", "netstat", "ifconfig", "route", "curl", "sw_vers", "stat", "wc",
        "tr", "grep", "find", "sed", "awk", "cat", "date", "sleep", "nohup", "env",
        "bash", "sh", "zsh", "sudo", "zest-smc"
    ]

    // Returns the display name to accumulate under, or nil to skip. Everything real is kept;
    // Zest's own sampling tools fold into "Zest".
    private func mapped(_ name: String) -> String? {
        if name.isEmpty || summaryRows.contains(name) { return nil }
        if foldToZest.contains(name) { return "Zest" }
        return name
    }

    // All sampling and every touch of `hourly` / `hourlyCount` happen on this one serial
    // queue. The old code dispatched each tick to the global pool, so a powermetrics run
    // that outlived the 12 s interval overlapped the next tick and both mutated the history
    // dictionaries at once (audit Z-B4).
    private let sampleQueue = DispatchQueue(label: "com.shanky.zest.energy-sampler", qos: .utility)
    private var inFlight = false   // main-thread only

    init() {
        loadHistory()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in self?.sample() }
    }
    deinit { timer?.invalidate() }

    private func sample() {
        // Skip a tick rather than queue up behind a slow one; the next tick catches up.
        guard !inFlight else { return }
        inFlight = true
        sampleQueue.async {
            let (live, pm) = self.readLiveEnergy()
            self.recordHistory(live)
            let win = self.buildWindows(live)
            DispatchQueue.main.async { self.window = win; self.usingPowermetrics = pm; self.inFlight = false }
        }
    }

    private func readLiveEnergy() -> ([String: Double], Bool) {
        if let pm = readPowermetricsEnergy(), !pm.isEmpty { return (pm, true) }
        return (readCPUProxy(), false)
    }

    private func readPowermetricsEnergy() -> [String: Double]? {
        let out = Shell.run("sudo -n /usr/bin/powermetrics --samplers tasks -n 1 -i 400 2>/dev/null", timeout: 6)
        guard out.lowercased().contains("ms/s") else { return nil }
        var totals: [String: Double] = [:]
        var inTable = false
        for line in out.components(separatedBy: "\n") {
            if line.contains("ID") && line.lowercased().contains("cpu ms/s") { inTable = true; continue }
            guard inTable else { continue }
            let toks = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard toks.count >= 3, let pidIdx = toks.firstIndex(where: { Int($0) != nil }), pidIdx >= 1, pidIdx + 1 < toks.count else { continue }
            let raw = toks[0..<pidIdx].joined(separator: " ")
            guard let name = mapped(appName(from: raw)), let cpuMs = Double(toks[pidIdx + 1]), cpuMs > 0.5 else { continue }
            totals[name, default: 0] += cpuMs
        }
        return totals.isEmpty ? nil : totals
    }

    private func readCPUProxy() -> [String: Double] {
        let out = Shell.run("/bin/ps -Aceo pcpu,comm 2>/dev/null", timeout: 6)
        var totals: [String: Double] = [:]
        for line in out.components(separatedBy: "\n").dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let spaceIdx = trimmed.firstIndex(of: " ") else { continue }
            let cpuStr = String(trimmed[..<spaceIdx])
            let comm = String(trimmed[trimmed.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespaces)
            guard let cpu = Double(cpuStr), cpu > 0.1 else { continue }
            guard let name = mapped(appName(from: comm)) else { continue }
            totals[name, default: 0] += cpu
        }
        return totals
    }

    private func appName(from comm: String) -> String {
        if let r = comm.range(of: ".app/") {
            let before = comm[..<r.lowerBound]
            if let slash = before.range(of: "/", options: .backwards) { return String(before[slash.upperBound...]) }
        }
        return (comm as NSString).lastPathComponent
    }

    // Keys are UTC (TimeKeys) since 2026-09-05; the parsed-key cache is confined to
    // sampleQueue. The old code built a fresh DateFormatter in the local zone for every
    // bucket on every pass (three window averages, a seven-day average per live app, and
    // the prune: roughly 8,600 formatter allocations per 12 s tick over a 30-day history),
    // which with the 4.6 MB history rewrite below was most of Zest's idle CPU.
    private var hourKeyDates: [String: Date] = [:]
    private var lastSave: Date = .distantPast
    private var lastPrune: Date = .distantPast
    private let saveInterval: TimeInterval = 300
    static let keyZoneTag = "UTC"

    private func hourKey(_ date: Date = Date()) -> String { TimeKeys.hourKey(date) }
    private func dateFromHourKey(_ key: String) -> Date? {
        if let d = hourKeyDates[key] { return d }
        guard let d = TimeKeys.date(fromHourKey: key) else { return nil }
        hourKeyDates[key] = d
        return d
    }

    // Re-keys a history written with local-zone keys into UTC, merging buckets that land
    // on the same UTC hour. Pure so the migration is testable; `zone` is the zone the old
    // keys were written in (the Mac's zone at migration time).
    static func rekeyToUTC(hourly: [String: [String: Double]], counts: [String: Int], from zone: TimeZone)
        -> (hourly: [String: [String: Double]], counts: [String: Int]) {
        var h: [String: [String: Double]] = [:]
        var c: [String: Int] = [:]
        for (oldKey, bucket) in hourly {
            guard let newKey = TimeKeys.hourKey(rekeying: oldKey, from: zone) else { continue }
            var merged = h[newKey] ?? [:]
            for (app, v) in bucket { merged[app, default: 0] += v }
            h[newKey] = merged
            c[newKey, default: 0] += counts[oldKey] ?? 0
        }
        return (h, c)
    }

    private func recordHistory(_ live: [String: Double]) {
        if firstTS == 0 { firstTS = Date().timeIntervalSince1970; saveMeta() }
        let key = hourKey()
        var bucket = hourly[key] ?? [:]
        for (app, v) in live { bucket[app, default: 0] += v }
        hourly[key] = bucket
        hourlyCount[key, default: 0] += 1
        // Prune hourly and persist every five minutes instead of rewriting the multi-MB
        // history file on every 12 s tick; shutdown() flushes the tail.
        if Date().timeIntervalSince(lastPrune) > 3600 { prune(); lastPrune = Date() }
        if Date().timeIntervalSince(lastSave) > saveInterval { saveHistory(); lastSave = Date() }
    }

    // Called from AppState.shutdown() so the last few minutes survive a quit.
    func flush() { sampleQueue.sync { saveHistory() } }

    private func buildWindows(_ live: [String: Double]) -> Window {
        var w = Window()
        w.startedAt = firstTS > 0 ? Date(timeIntervalSince1970: firstTS) : nil
        w.spanHours = firstTS > 0 ? (Date().timeIntervalSince1970 - firstTS) / 3600 : 0
        w.live = live.sorted { $0.value > $1.value }.prefix(8).map {
            AppEnergy(name: $0.key, value: $0.value, isMisbehaving: isMisbehaving($0.key, current: $0.value))
        }
        w.significant = significantApps(live)
        w.totalLive = live.values.reduce(0, +)
        w.last24h = average(hoursBack: 24)
        w.last7d = average(hoursBack: 24 * 7)
        w.last30d = average(hoursBack: 24 * 30)
        w.spark24h = sparkline(hoursBack: 24)
        return w
    }

    // Average ms/s per app across the collected buckets in the window.
    private func average(hoursBack: Int) -> [AppEnergy] {
        let cutoff = Calendar.current.date(byAdding: .hour, value: -hoursBack, to: Date())!
        var sums: [String: Double] = [:]
        var samples = 0
        for (key, bucket) in hourly {
            guard let d = dateFromHourKey(key), d >= cutoff else { continue }
            samples += hourlyCount[key] ?? 0
            for (app, v) in bucket { sums[app, default: 0] += v }
        }
        guard samples > 0 else { return [] }
        return sums.mapValues { $0 / Double(samples) }
            .sorted { $0.value > $1.value }.prefix(8)
            .map { AppEnergy(name: $0.key, value: $0.value, isMisbehaving: false) }
    }

    private func sparkline(hoursBack: Int) -> [Double] {
        var out: [Double] = []
        for i in stride(from: hoursBack - 1, through: 0, by: -1) {
            let d = Calendar.current.date(byAdding: .hour, value: -i, to: Date())!
            let key = hourKey(d)
            let count = hourlyCount[key] ?? 0
            let sum = (hourly[key] ?? [:]).values.reduce(0, +)
            out.append(count > 0 ? sum / Double(count) : 0)   // average ms/s that hour
        }
        return out
    }

    // Apps currently drawing above the threshold, aggregated to the app level (helper
    // processes fold into their parent app, e.g. Chrome renderers into Google Chrome).
    private func significantApps(_ live: [String: Double]) -> [AppEnergy] {
        var agg: [String: Double] = [:]
        for (name, v) in live { agg[displayApp(name), default: 0] += v }
        return agg.filter { $0.value >= significantThreshold }
            .sorted { $0.value > $1.value }.prefix(6)
            .map { AppEnergy(name: $0.key, value: $0.value, isMisbehaving: false) }
    }
    private func displayApp(_ name: String) -> String {
        if let r = name.range(of: " Helper") { return String(name[..<r.lowerBound]) }
        return name
    }

    private func isMisbehaving(_ app: String, current: Double) -> Bool {
        current > max(50, sevenDayAverage(app) * 2)
    }
    private func sevenDayAverage(_ app: String) -> Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        var sum = 0.0, samples = 0
        for (key, bucket) in hourly {
            guard let d = dateFromHourKey(key), d >= cutoff else { continue }
            if let v = bucket[app] { sum += v; samples += hourlyCount[key] ?? 0 }
        }
        return samples > 0 ? sum / Double(samples) : 0
    }

    private func prune() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let keep = Set(hourly.keys.filter { dateFromHourKey($0).map { $0 >= cutoff } ?? false })
        hourly = hourly.filter { keep.contains($0.key) }
        hourlyCount = hourlyCount.filter { keep.contains($0.key) }
        hourKeyDates = hourKeyDates.filter { keep.contains($0.key) }
    }
    private func saveHistory() {
        try? FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let payload: [String: Any] = ["hourly": hourly, "counts": hourlyCount]
        if let data = try? JSONSerialization.data(withJSONObject: payload) { try? data.write(to: historyURL, options: .atomic) }
    }
    private func saveMeta() {
        let meta: [String: Any] = ["firstTS": firstTS, "keyZone": Self.keyZoneTag]
        if let data = try? JSONSerialization.data(withJSONObject: meta) { try? data.write(to: metaURL, options: .atomic) }
    }
    private func loadHistory() {
        if let data = try? Data(contentsOf: historyURL), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            hourly = (obj["hourly"] as? [String: [String: Double]]) ?? [:]
            hourlyCount = (obj["counts"] as? [String: Int]) ?? [:]
        }
        var keyZone: String? = nil
        if let data = try? Data(contentsOf: metaURL), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            firstTS = (obj["firstTS"] as? Double) ?? 0
            keyZone = obj["keyZone"] as? String
        }
        // One-time migration: histories written before 2026-09-05 carry local-zone keys
        // and no keyZone tag. Re-key them in the zone this Mac is in right now (the zone
        // they were written in, as long as the migration runs before the Mac moves).
        if keyZone != Self.keyZoneTag, !hourly.isEmpty {
            let migrated = Self.rekeyToUTC(hourly: hourly, counts: hourlyCount, from: TimeZone.current)
            hourly = migrated.hourly
            hourlyCount = migrated.counts
            saveHistory()
            saveMeta()
            NSLog("Zest: energy history re-keyed from \(TimeZone.current.identifier) to UTC (\(hourly.count) buckets)")
        } else if keyZone != Self.keyZoneTag {
            saveMeta()
        }
    }
}
