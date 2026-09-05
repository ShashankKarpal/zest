import Foundation
import Combine
import IOKit
import IOKit.ps

// Reads the internal battery via IOKit power sources (fast, push-notified) and the
// IORegistry AppleSmartBattery entry (detail keys, and since 2026-09-05 also cycle count
// and maximum capacity, which the registry carries directly). Only the Condition string
// still comes from system_profiler, refreshed at most hourly and always off the main
// thread; the old code ran that 2 to 12 s command synchronously inside refresh() on the
// main thread (audit Z-B2). Event-driven so idle CPU stays negligible.
final class BatteryService: ObservableObject {
    @Published private(set) var snapshot = BatterySnapshot()

    private var runLoopSource: CFRunLoopSource?
    private var pollTimer: Timer?
    private var conditionTime: Date = .distantPast
    private var conditionInFlight = false
    private var lastRegistry: [String: Any] = [:]

    private var thermalObserver: NSObjectProtocol?

    init() {
        refresh()
        startNotifications()
        // Light backstop poll so detail values (temp, watts) stay live even between events.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // Thermal pressure is pushed by the system; fold it into the next snapshot at once.
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let s = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), s, .defaultMode) }
        pollTimer?.invalidate()
        if let o = thermalObserver { NotificationCenter.default.removeObserver(o) }
    }

    private func startNotifications() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let cb: IOPowerSourceCallbackType = { context in
            guard let context = context else { return }
            let me = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { me.refresh() }
        }
        if let src = IOPSNotificationCreateRunLoopSource(cb, ctx)?.takeRetainedValue() {
            runLoopSource = src
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .defaultMode)
        }
    }

    func refresh() {
        var snap = BatterySnapshot()
        readPowerSources(into: &snap)
        readIORegistry(into: &snap)
        readHealth(into: &snap)
        snap.thermalState = ProcessInfo.processInfo.thermalState
        if snap != snapshot { snapshot = snap }
    }

    // MARK: IOKit power sources
    private func readPowerSources(into snap: inout BatterySnapshot) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any] else { continue }
            if let cap = desc[kIOPSCurrentCapacityKey as String] as? Int { snap.percent = cap }
            if let state = desc[kIOPSPowerSourceStateKey as String] as? String {
                snap.isACPower = (state == kIOPSACPowerValue)
            }
            if let charging = desc[kIOPSIsChargingKey as String] as? Bool { snap.isCharging = charging }
            if let charged = desc[kIOPSIsChargedKey as String] as? Bool { snap.fullyCharged = charged }
            if snap.isCharging {
                if let toFull = desc[kIOPSTimeToFullChargeKey as String] as? Int, toFull > 0 {
                    snap.timeRemainingMinutes = toFull; snap.timeIsToFull = true
                }
            } else if !snap.isACPower {
                if let toEmpty = desc[kIOPSTimeToEmptyKey as String] as? Int, toEmpty > 0 {
                    snap.timeRemainingMinutes = toEmpty; snap.timeIsToFull = false
                }
            }
        }
    }

    // MARK: IORegistry AppleSmartBattery
    private func readIORegistry(into snap: inout BatterySnapshot) {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard entry != 0 else { return }
        defer { IOObjectRelease(entry) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return }
        lastRegistry = dict

        if let t = dict["Temperature"] as? Int { snap.temperatureC = Double(t) / 100.0 }
        if let v = dict["Voltage"] as? Int { snap.voltageV = Double(v) / 1000.0 }
        if let a = dict["InstantAmperage"] as? Int { snap.amperageMA = signedAmperage(a) }
        else if let a = dict["Amperage"] as? Int { snap.amperageMA = signedAmperage(a) }
        if let d = dict["DesignCapacity"] as? Int { snap.designCapacityMAh = d }
        if let m = dict["AppleRawMaxCapacity"] as? Int { snap.rawMaxCapacityMAh = m }
        if let ext = dict["ExternalConnected"] as? Bool { snap.isACPower = ext }
        if let ch = dict["IsCharging"] as? Bool { snap.isCharging = ch }
        if let full = dict["FullyCharged"] as? Bool { snap.fullyCharged = full }

        if let ad = dict["AdapterDetails"] as? [String: Any] {
            snap.adapterWatts = ad["Watts"] as? Int
            snap.adapterName = ad["Name"] as? String
            if let mv = ad["AdapterVoltage"] as? Int { snap.adapterVoltage = Double(mv) / 1000.0 }
            snap.adapterCurrentMA = ad["Current"] as? Int
        }
    }

    // IOKit stores InstantAmperage as an unsigned 64-bit value; large values are negative.
    private func signedAmperage(_ raw: Int) -> Int {
        if raw > Int(Int32.max) { return raw - Int(UInt32.max) - 1 }
        return raw
    }

    // MARK: Health
    // Cycle count comes from the registry dictionary read above, on every refresh (it is
    // the same number system_profiler prints). Maximum Capacity and Condition still come
    // from system_profiler: the registry has no key that reproduces Apple's displayed
    // percentage (on the 2026-09-05 M4 Pro it showed 99 while AppleRawMaxCapacity/Design
    // gave 96 and NominalChargeCapacity/Design gave 98), and Condition has no registry
    // equivalent at all. What changed: that command now runs hourly OFF the main thread
    // (it took 2 to 12 s inside refresh() on the main thread before, audit Z-B2), and until
    // its first result lands the snapshot carries the registry ratio as a fallback.
    private func readHealth(into snap: inout BatterySnapshot) {
        let reg = Self.health(fromRegistry: lastRegistry)
        snap.cycleCount = reg.cycles
        snap.maxCapacityPercent = profiler?.maxCap ?? reg.maxCap
        snap.condition = profiler?.condition
        refreshProfilerIfStale()
    }

    struct Health: Equatable {
        var cycles: Int?
        var maxCap: Int?
        var condition: String?
    }

    // Registry-only view: exact cycle count, capacity as a raw/design fallback ratio.
    static func health(fromRegistry dict: [String: Any]) -> Health {
        let cycles = dict["CycleCount"] as? Int
        var maxCap: Int? = nil
        if let d = dict["DesignCapacity"] as? Int, let m = dict["AppleRawMaxCapacity"] as? Int, d > 0 {
            maxCap = Int((Double(m) / Double(d) * 100).rounded())
        }
        return Health(cycles: cycles, maxCap: maxCap, condition: nil)
    }

    // system_profiler SPPowerDataType text view.
    static func health(fromProfilerText text: String) -> Health {
        Health(cycles: firstMatch(text, #"Cycle Count:\s*(\d+)"#).flatMap { Int($0) },
               maxCap: firstMatch(text, #"Maximum Capacity:\s*(\d+)%"#).flatMap { Int($0) },
               condition: firstMatch(text, #"Condition:\s*([A-Za-z ]+?)\s*$"#, options: .anchorsMatchLines))
    }

    private var profiler: Health?
    private func refreshProfilerIfStale() {
        guard !conditionInFlight, Date().timeIntervalSince(conditionTime) > 3600 else { return }
        conditionInFlight = true
        DispatchQueue.global(qos: .utility).async {
            let out = Shell.run("/usr/sbin/system_profiler SPPowerDataType", timeout: 12)
            let h = Self.health(fromProfilerText: out)
            DispatchQueue.main.async {
                self.conditionInFlight = false
                self.conditionTime = Date()
                // A failed run (empty output) keeps the previous values rather than blanking them.
                guard h.maxCap != nil || h.condition != nil else { return }
                if h != self.profiler { self.profiler = h; self.refresh() }
            }
        }
    }

    private static func firstMatch(_ text: String, _ pattern: String, options: NSRegularExpression.Options = []) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

}
