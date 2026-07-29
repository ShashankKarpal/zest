import Foundation
import Combine

// Discovers auxiliary device battery levels using the same three-strategy merge proven
// in the System Vitals fetch.py: ioreg BatteryPercent keys, system_profiler Bluetooth
// walker (device_batteryLevelLeft/Right/Case/Main), and the CoreBluetooth GATT cache
// written by the existing blebattery helper. Duty-cycled with a 30s cache TTL so the
// Bluetooth radio impact stays near zero.
final class DevicesService: ObservableObject {
    @Published private(set) var devices: [AuxDevice] = []

    private var timer: Timer?
    private let bleCachePath = NSString(string: "~/../tmp/ubersicht-ble-battery.json").expandingTildeInPath
    private let bleCacheTTL: TimeInterval = 900

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
    }
    deinit { timer?.invalidate() }

    func refresh() {
        DispatchQueue.global(qos: .utility).async {
            var merged: [String: AuxDevice] = [:]
            func add(_ d: AuxDevice) {
                let key = d.name.lowercased()
                if let existing = merged[key] {
                    // Prefer the entry with the most detail.
                    let existingFields = [existing.battery, existing.left, existing.right, existing.caseLevel].compactMap { $0 }.count
                    let newFields = [d.battery, d.left, d.right, d.caseLevel].compactMap { $0 }.count
                    if newFields > existingFields { merged[key] = d }
                } else {
                    merged[key] = d
                }
            }
            self.bluetoothDevices().forEach(add)
            self.bleCacheDevices().forEach(add)
            self.hidDevices().forEach(add)

            let list = merged.values.sorted { $0.sortLevel < $1.sortLevel }
            DispatchQueue.main.async { self.devices = list }
        }
    }

    // MARK: system_profiler SPBluetoothDataType
    private func bluetoothDevices() -> [AuxDevice] {
        guard let obj = Shell.runJSON("/usr/sbin/system_profiler SPBluetoothDataType -json", timeout: 15) else { return [] }
        var found: [AuxDevice] = []
        func level(_ v: Any?) -> Int? {
            guard let s = v as? String else { return v as? Int }
            let digits = s.filter { $0.isNumber }
            return Int(digits)
        }
        func walk(_ any: Any, name: String?) {
            if let dict = any as? [String: Any] {
                let main = level(dict["device_batteryLevelMain"])
                let l = level(dict["device_batteryLevelLeft"])
                let r = level(dict["device_batteryLevelRight"])
                let c = level(dict["device_batteryLevelCase"])
                if (main != nil || l != nil || r != nil || c != nil), let name = name {
                    found.append(AuxDevice(name: name, battery: main, left: l, right: r, caseLevel: c, source: "bt"))
                }
                for (k, v) in dict {
                    if v is [String: Any] { walk(v, name: k) }
                    else if v is [Any] { walk(v, name: name) }
                }
            } else if let arr = any as? [Any] {
                for item in arr { walk(item, name: name) }
            }
        }
        walk(obj, name: nil)
        return found
    }

    // MARK: blebattery JSON cache (CoreBluetooth GATT 0x180F)
    private func bleCacheDevices() -> [AuxDevice] {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: bleCachePath),
              let mod = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(mod) < bleCacheTTL,
              let data = FileManager.default.contents(atPath: bleCachePath),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["devices"] as? [[String: Any]] else { return [] }
        return list.compactMap { d in
            guard let name = d["name"] as? String, let batt = d["battery"] as? Int, (0...100).contains(batt) else { return nil }
            return AuxDevice(name: name, battery: batt, left: nil, right: nil, caseLevel: nil, source: "ble")
        }
    }

    // MARK: ioreg HID walker
    private func hidDevices() -> [AuxDevice] {
        var found: [AuxDevice] = []
        var seen = Set<String>()
        func scan(_ command: String) {
            let out = Shell.run(command, timeout: 6)
            // ioreg -a plist output; parse lightly for "Product" + a battery integer near it.
            // Fall back to a simple line scan on key/value pairs.
            let lines = out.components(separatedBy: "\n")
            var lastProduct: String?
            for line in lines {
                if let name = capture(line, #"\"Product\"\s*=\s*\"([^\"]+)\""#) { lastProduct = name }
                if let name = capture(line, #"\"BluetoothProductName\"\s*=\s*\"([^\"]+)\""#) { lastProduct = name }
                if let valStr = capture(line, #"\"Battery(?:Percent|Percentage)\"\s*=\s*(\d+)"#),
                   let val = Int(valStr), (0...100).contains(val), let name = lastProduct {
                    let key = name.lowercased()
                    if !seen.contains(key) { seen.insert(key); found.append(AuxDevice(name: name, battery: val, left: nil, right: nil, caseLevel: nil, source: "hid")) }
                }
            }
        }
        scan("/usr/sbin/ioreg -r -k BatteryPercent -a 2>/dev/null")
        if found.isEmpty { scan("/usr/sbin/ioreg -a -l -r -c AppleHSBluetoothDevice 2>/dev/null") }
        return found
    }

    private func capture(_ line: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let m = re.firstMatch(in: line, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: line) else { return nil }
        return String(line[r])
    }
}
