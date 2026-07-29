import Foundation
import Combine

// iPhone / iPad battery health over USB via libimobiledevice (brew). macOS does not expose
// iOS battery HEALTH wirelessly, so this uses a cable and reads it directly. Level and
// charging state are reliable; cycle count and capacity are best-effort (they depend on the
// device being unlocked and trusted, and on the iOS version). Degrades gracefully when the
// tools are absent or no device is connected. Everything is processed locally.
final class IOSDeviceService: ObservableObject {
    struct Device: Identifiable, Equatable {
        var id: String { udid }
        var udid: String
        var name: String
        var product: String
        var level: Int?
        var charging: Bool
        var cycleCount: Int?
        var maxCapacity: Int?
    }

    @Published private(set) var devices: [Device] = []
    @Published private(set) var toolsInstalled = false
    @Published private(set) var status = "Connect an iPhone or iPad by cable to see its battery health."

    private var timer: Timer?
    private let idevice_id = "/opt/homebrew/bin/idevice_id"
    private let ideviceinfo = "/opt/homebrew/bin/ideviceinfo"
    private let idevicediag = "/opt/homebrew/bin/idevicediagnostics"

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
    }
    deinit { timer?.invalidate() }

    func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let installed = FileManager.default.isExecutableFile(atPath: self.idevice_id)
            guard installed else {
                DispatchQueue.main.async {
                    self.toolsInstalled = false
                    self.status = "Install libimobiledevice (brew install libimobiledevice) to read iPhone and iPad battery health."
                    self.devices = []
                }
                return
            }
            let udids = Shell.run("\(self.idevice_id) -l 2>/dev/null", timeout: 6)
                .components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            var found: [Device] = []
            for udid in udids { if let d = self.read(udid) { found.append(d) } }
            DispatchQueue.main.async {
                self.toolsInstalled = true
                self.devices = found
                self.status = found.isEmpty
                    ? "No iPhone or iPad detected. Connect by cable and tap Trust on the device."
                    : "\(found.count) device\(found.count == 1 ? "" : "s") connected."
            }
        }
    }

    private func read(_ udid: String) -> Device? {
        let info = Shell.run("\(ideviceinfo) -u \(q(udid)) 2>/dev/null", timeout: 8)
        let name = value(info, "DeviceName") ?? "iOS device"
        let product = value(info, "ProductType") ?? ""
        let batt = Shell.run("\(ideviceinfo) -u \(q(udid)) -q com.apple.mobile.battery 2>/dev/null", timeout: 8)
        let level = value(batt, "BatteryCurrentCapacity").flatMap { Int($0) }
        let charging = (value(batt, "BatteryIsCharging") ?? "").lowercased() == "true"

        // Best-effort deep health from the diagnostics relay (needs unlock + trust).
        var cycles: Int? = nil
        var maxCap: Int? = nil
        let io = Shell.run("\(idevicediag) -u \(q(udid)) ioregentry AppleSmartBattery 2>/dev/null", timeout: 8)
        if !io.isEmpty {
            cycles = plistInt(io, "CycleCount")
            if let raw = plistInt(io, "AppleRawMaxCapacity"), let design = plistInt(io, "DesignCapacity"), design > 0 {
                maxCap = Int((Double(raw) / Double(design) * 100).rounded())
            } else if let nom = plistInt(io, "NominalChargeCapacity"), let design = plistInt(io, "DesignCapacity"), design > 0 {
                maxCap = Int((Double(nom) / Double(design) * 100).rounded())
            }
        }
        return Device(udid: udid, name: name, product: product, level: level, charging: charging, cycleCount: cycles, maxCapacity: maxCap)
    }

    // ideviceinfo prints "Key: value" lines.
    private func value(_ text: String, _ key: String) -> String? {
        for line in text.components(separatedBy: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0] == key { return parts[1] }
        }
        return nil
    }
    // ioregentry prints an XML plist; pull an <integer> that follows <key>NAME</key>.
    private func plistInt(_ xml: String, _ key: String) -> Int? {
        guard let keyRange = xml.range(of: "<key>\(key)</key>") else { return nil }
        let after = xml[keyRange.upperBound...]
        guard let intOpen = after.range(of: "<integer>"), let intClose = after.range(of: "</integer>"),
              intOpen.upperBound < intClose.lowerBound else { return nil }
        return Int(after[intOpen.upperBound..<intClose.lowerBound].trimmingCharacters(in: .whitespaces))
    }
    private func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
