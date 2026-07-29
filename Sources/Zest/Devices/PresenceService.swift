import Foundation
import Combine

// Detects device presence locally: which Bluetooth devices are currently connected (by
// address), and which IPs/MACs are on the local network (arp). This lets the Ecosystem view
// remember a device by a stable identifier and show it as connected or on Wi-Fi even when
// macOS does not expose its battery (for example an iPhone over Bluetooth). All local.
final class PresenceService: ObservableObject {
    struct BTDevice: Identifiable, Equatable {
        var id: String { address }
        var name: String
        var address: String
        var minorType: String
        var connected: Bool
    }

    @Published private(set) var btDevices: [BTDevice] = []      // for the picker
    @Published private(set) var connectedAddresses: Set<String> = []
    @Published private(set) var lanIPs: Set<String> = []
    @Published private(set) var lanMACs: Set<String> = []

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
    }
    deinit { timer?.invalidate() }

    func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let bt = self.scanBluetooth()
            let (ips, macs) = self.scanLAN()
            DispatchQueue.main.async {
                self.btDevices = bt.sorted { $0.name.lowercased() < $1.name.lowercased() }
                self.connectedAddresses = Set(bt.filter { $0.connected }.map { $0.address.lowercased() })
                self.lanIPs = ips
                self.lanMACs = macs
            }
        }
    }

    private func scanBluetooth() -> [BTDevice] {
        guard let obj = Shell.runJSON("/usr/sbin/system_profiler SPBluetoothDataType -json", timeout: 15),
              let controllers = obj["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var out: [BTDevice] = []
        for controller in controllers {
            for (section, connected) in [("device_connected", true), ("device_not_connected", false)] {
                guard let arr = controller[section] as? [[String: Any]] else { continue }
                for entry in arr {
                    for (name, attrsAny) in entry {
                        guard let attrs = attrsAny as? [String: Any] else { continue }
                        let address = (attrs["device_address"] as? String) ?? ""
                        guard !address.isEmpty else { continue }
                        let minor = (attrs["device_minorType"] as? String) ?? (attrs["device_majorType"] as? String) ?? ""
                        out.append(BTDevice(name: name, address: address, minorType: minor, connected: connected))
                    }
                }
            }
        }
        return out
    }

    private func scanLAN() -> (Set<String>, Set<String>) {
        let out = Shell.run("/usr/sbin/arp -an 2>/dev/null", timeout: 5)
        var ips = Set<String>(), macs = Set<String>()
        for line in out.components(separatedBy: "\n") {
            // Format: ? (10.0.0.2) at aa:bb:cc:dd:ee:ff on en0 ...
            if let ipR = firstMatch(line, #"\((\d+\.\d+\.\d+\.\d+)\)"#) { ips.insert(ipR) }
            if let macR = firstMatch(line, #"at ([0-9a-fA-F:]+) on"#) { macs.insert(normalizeMAC(macR)) }
        }
        return (ips, macs)
    }

    // arp prints MACs without leading zeros (d:7:80); normalize both sides for comparison.
    func normalizeMAC(_ mac: String) -> String {
        mac.split(separator: ":").map { seg -> String in
            let s = String(seg).lowercased()
            return s.count == 1 ? "0" + s : s
        }.joined(separator: ":")
    }

    func lanContains(_ id: String) -> Bool {
        let t = id.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        if t.contains(".") { return lanIPs.contains(t) }
        return lanMACs.contains(normalizeMAC(t))
    }

    private func firstMatch(_ text: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
