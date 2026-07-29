import Foundation
import Combine
import IOKit
import IOKit.ps

// Reads the internal battery via IOKit power sources (fast, push-notified) and the
// IORegistry AppleSmartBattery entry (detail keys). Health (cycles, capacity, condition)
// comes from system_profiler, cached for an hour to keep it cheap. Event-driven so idle
// CPU stays negligible, matching the native app's design goal.
final class BatteryService: ObservableObject {
    @Published private(set) var snapshot = BatterySnapshot()

    private var runLoopSource: CFRunLoopSource?
    private var pollTimer: Timer?
    private var healthCache: (cycles: Int?, maxCap: Int?, condition: String?)?
    private var healthCacheTime: Date = .distantPast

    init() {
        refresh()
        startNotifications()
        // Light backstop poll so detail values (temp, watts) stay live even between events.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let s = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), s, .defaultMode) }
        pollTimer?.invalidate()
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

    // MARK: Health via system_profiler (cached 1h)
    private func readHealth(into snap: inout BatterySnapshot) {
        if healthCache == nil || Date().timeIntervalSince(healthCacheTime) > 3600 {
            let out = Shell.run("/usr/sbin/system_profiler SPPowerDataType", timeout: 12)
            let cyc = firstMatch(out, #"Cycle Count:\s*(\d+)"#).flatMap { Int($0) }
            let cap = firstMatch(out, #"Maximum Capacity:\s*(\d+)%"#).flatMap { Int($0) }
            let cond = firstMatch(out, #"Condition:\s*(\w+)"#)
            healthCache = (cyc, cap, cond)
            healthCacheTime = Date()
        }
        if let h = healthCache {
            snap.cycleCount = h.cycles
            snap.maxCapacityPercent = h.maxCap
            snap.condition = h.condition
        }
        // Fallback capacity from raw values if system_profiler was unavailable.
        if snap.maxCapacityPercent == nil, let d = snap.designCapacityMAh, let m = snap.rawMaxCapacityMAh, d > 0 {
            snap.maxCapacityPercent = Int((Double(m) / Double(d) * 100).rounded())
        }
    }

    private func firstMatch(_ text: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
