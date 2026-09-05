import Foundation
import Combine

// Persistent user config. Single JSON file in ~/Library/Application Support/Zest/config.json.
// No license fields, no accounts. Personal use only.

enum AlertDirection: String, Codable { case falling, rising }
enum PillSize: String, Codable, CaseIterable { case xs, s, def, l
    var multiplier: CGFloat { switch self { case .xs: return 0.75; case .s: return 0.88; case .def: return 1.0; case .l: return 1.2 } }
    var label: String { switch self { case .xs: return "Extra Small"; case .s: return "Smaller"; case .def: return "Default"; case .l: return "Larger" } }
}
enum PillPosition: String, Codable, CaseIterable {
    case topLeft, topCenter, topRight, midLeft, center, midRight, bottomLeft, bottomCenter, bottomRight
    var label: String {
        switch self {
        case .topLeft: return "Top Left"; case .topCenter: return "Top Center"; case .topRight: return "Top Right"
        case .midLeft: return "Mid Left"; case .center: return "Center"; case .midRight: return "Mid Right"
        case .bottomLeft: return "Bottom Left"; case .bottomCenter: return "Bottom Center"; case .bottomRight: return "Bottom Right"
        }
    }
}

struct BatteryAlertRule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var threshold: Int              // percent
    var direction: AlertDirection   // falling = fires on drop below, rising = fires on rise above
    var enabled: Bool = true
    var persistent: Bool = false
    var glow: Bool = true
    var sound: String = "Glass"     // system sound name or imported file basename
    var colorHex: UInt32 = 0xF59E0B
    var position: PillPosition = .topRight
}

enum LifecycleEvent: String, Codable, CaseIterable {
    case pluggedIn, unpluggedFrom, chargedAbove80, fullyCharged
    var label: String {
        switch self {
        case .pluggedIn: return "Charger plugged in"
        case .unpluggedFrom: return "Unplugged"
        case .chargedAbove80: return "Charged above 80%"
        case .fullyCharged: return "Fully charged (100%)"
        }
    }
}

struct LifecycleRule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var event: LifecycleEvent
    var enabled: Bool = true
    var persistent: Bool = false
    var glow: Bool = false
    var sound: String = "Ping"
}

struct DeviceAlertRule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var deviceName: String
    var lowThreshold: Int = 10
    var lowEnabled: Bool = true
    var fullEnabled: Bool = false
    var sound: String = "Tink"
    var colorHex: UInt32 = 0xEF4444
}

// Optional Claude usage readout shown in the menu bar next to the battery icon.
enum MenuBarClaudeMode: String, Codable, CaseIterable {
    case off, acct1Session, acct1Weekly, acct2Session, acct2Weekly
    var label: String {
        switch self {
        case .off: return "Off"
        case .acct1Session: return "Account 1 session %"
        case .acct1Weekly: return "Account 1 weekly %"
        case .acct2Session: return "Account 2 session %"
        case .acct2Weekly: return "Account 2 weekly %"
        }
    }
    var tag: String {
        switch self {
        case .off: return ""
        case .acct1Session, .acct1Weekly: return "A1"
        case .acct2Session, .acct2Weekly: return "A2"
        }
    }
    var usesWeekly: Bool { self == .acct1Weekly || self == .acct2Weekly }
    var usesAcct2: Bool { self == .acct2Session || self == .acct2Weekly }
}

struct MenuBarStyle: Codable, Equatable {
    var showPercentInsideIcon: Bool = true
    var showTimeRemaining: Bool = false      // show time instead of %
    var statusColors: Bool = true            // color icon by level/charge
    var hideNumber: Bool = false             // clean minimal look
    var darkGlyph: Bool = false              // false = light glyph for dark menu bars
    var claudeMode: MenuBarClaudeMode = .off // optional Claude usage readout

    init() {}
    // Tolerant decode so a saved config from an earlier build keeps its other menu bar prefs.
    enum CodingKeys: String, CodingKey { case showPercentInsideIcon, showTimeRemaining, statusColors, hideNumber, darkGlyph, claudeMode }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        showPercentInsideIcon = (try? c.decode(Bool.self, forKey: .showPercentInsideIcon)) ?? true
        showTimeRemaining = (try? c.decode(Bool.self, forKey: .showTimeRemaining)) ?? false
        statusColors = (try? c.decode(Bool.self, forKey: .statusColors)) ?? true
        hideNumber = (try? c.decode(Bool.self, forKey: .hideNumber)) ?? false
        darkGlyph = (try? c.decode(Bool.self, forKey: .darkGlyph)) ?? false
        claudeMode = (try? c.decode(MenuBarClaudeMode.self, forKey: .claudeMode)) ?? .off
    }
}

struct QuietHours: Codable, Equatable {
    var enabled: Bool = false
    var startHour: Int = 22      // 10 PM
    var endHour: Int = 8         // 8 AM
    var allowCritical: Bool = true   // still fire a critical low-battery alert
    var criticalPercent: Int = 10
    // True if `hour` falls in the quiet window (handles overnight wrap).
    func contains(hour: Int) -> Bool {
        guard enabled else { return false }
        if startHour == endHour { return false }
        if startHour < endHour { return hour >= startHour && hour < endHour }
        return hour >= startHour || hour < endHour   // wraps past midnight
    }
}

struct ChargeLimitConfig: Codable, Equatable {
    var enabled: Bool = false                // stays off until helper grant added
    var limit: Int = 80                      // 50...100
    var sailingMode: Bool = true
    var sailWidth: Int = 5                   // drift band below limit
    var automaticDischarge: Bool = false
    var heatProtection: Bool = true
    var heatCelsius: Int = 35
    var magSafeLED: Bool = true
}

// A device the user curates into their personal ecosystem. Zest shows live battery for the
// ones it can currently see (Bluetooth, Continuity, USB) and remembers the rest.
enum EcoDeviceType: String, Codable, CaseIterable {
    case mac, iphone, ipad, watch, airpods, other
    var label: String {
        switch self {
        case .mac: return "Mac"; case .iphone: return "iPhone"; case .ipad: return "iPad"
        case .watch: return "Apple Watch"; case .airpods: return "AirPods"; case .other: return "Other"
        }
    }
    var icon: String {
        switch self {
        case .mac: return "💻"; case .iphone: return "📱"; case .ipad: return "📲"
        case .watch: return "⌚"; case .airpods: return "🎧"; case .other: return "🔗"
        }
    }
}

struct EcoDevice: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var type: EcoDeviceType
    var matchHint: String = ""     // substring used to match a live device; defaults to name
    var btAddress: String = ""     // Bluetooth device address, robust match + presence
    var netID: String = ""         // Wi-Fi IP or MAC for LAN presence
    var isThisMac: Bool = false
    var effectiveHint: String { matchHint.isEmpty ? name : matchHint }

    enum CodingKeys: String, CodingKey { case id, name, type, matchHint, btAddress, netID, isThisMac }
    init(name: String, type: EcoDeviceType, matchHint: String = "", btAddress: String = "", netID: String = "", isThisMac: Bool = false) {
        self.name = name; self.type = type; self.matchHint = matchHint
        self.btAddress = btAddress; self.netID = netID; self.isThisMac = isThisMac
    }
    // Tolerant decode so entries saved before these fields existed still load.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? "Device"
        type = (try? c.decode(EcoDeviceType.self, forKey: .type)) ?? .other
        matchHint = (try? c.decode(String.self, forKey: .matchHint)) ?? ""
        btAddress = (try? c.decode(String.self, forKey: .btAddress)) ?? ""
        netID = (try? c.decode(String.self, forKey: .netID)) ?? ""
        isThisMac = (try? c.decode(Bool.self, forKey: .isThisMac)) ?? false
    }
}

final class AppConfig: ObservableObject, Codable {
    @Published var menuBar = MenuBarStyle()
    @Published var alerts: [BatteryAlertRule] = AppConfig.defaultAlerts()
    @Published var lifecycle: [LifecycleRule] = LifecycleEvent.allCases.map { LifecycleRule(event: $0, enabled: $0 == .chargedAbove80) }
    @Published var deviceAlerts: [DeviceAlertRule] = []
    @Published var hiddenDevices: [String] = []
    @Published var chargeLimit = ChargeLimitConfig()
    @Published var glowIntensity: Double = 0.6      // 0...1
    @Published var launchAtLogin: Bool = false
    @Published var autoDismissMacAlerts: Bool = false // requires Accessibility
    @Published var quietHours = QuietHours()
    @Published var ecosystem: [EcoDevice] = []
    // Folder holding the user's own panel scripts (acct1.sh, acct2.sh, vitals.sh, cc.sh),
    // produced by panels/extract-panels.py. nil (the default, and the public build's
    // state) hides the four panel sections and never spawns a script.
    @Published var panelsRoot: String? = nil

    var panelsEnabled: Bool { !(panelsRoot ?? "").isEmpty }

    static func defaultAlerts() -> [BatteryAlertRule] {
        [
            BatteryAlertRule(threshold: 20, direction: .falling, colorHex: 0xF59E0B, position: .topRight),
            BatteryAlertRule(threshold: 10, direction: .falling, glow: true, colorHex: 0xF97316, position: .topRight),
            BatteryAlertRule(threshold: 5, direction: .falling, persistent: true, glow: true, sound: "Sosumi", colorHex: 0xEF4444, position: .center),
            BatteryAlertRule(threshold: 80, direction: .rising, glow: false, sound: "Glass", colorHex: 0x32D74B, position: .topRight)
        ]
    }

    // MARK: Codable
    enum CodingKeys: String, CodingKey {
        case menuBar, alerts, lifecycle, deviceAlerts, hiddenDevices, chargeLimit, glowIntensity, launchAtLogin, autoDismissMacAlerts, quietHours, ecosystem, panelsRoot
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        menuBar = (try? c.decode(MenuBarStyle.self, forKey: .menuBar)) ?? MenuBarStyle()
        alerts = (try? c.decode([BatteryAlertRule].self, forKey: .alerts)) ?? AppConfig.defaultAlerts()
        lifecycle = (try? c.decode([LifecycleRule].self, forKey: .lifecycle)) ?? LifecycleEvent.allCases.map { LifecycleRule(event: $0) }
        deviceAlerts = (try? c.decode([DeviceAlertRule].self, forKey: .deviceAlerts)) ?? []
        hiddenDevices = (try? c.decode([String].self, forKey: .hiddenDevices)) ?? []
        chargeLimit = (try? c.decode(ChargeLimitConfig.self, forKey: .chargeLimit)) ?? ChargeLimitConfig()
        glowIntensity = (try? c.decode(Double.self, forKey: .glowIntensity)) ?? 0.6
        launchAtLogin = (try? c.decode(Bool.self, forKey: .launchAtLogin)) ?? false
        autoDismissMacAlerts = (try? c.decode(Bool.self, forKey: .autoDismissMacAlerts)) ?? false
        quietHours = (try? c.decode(QuietHours.self, forKey: .quietHours)) ?? QuietHours()
        ecosystem = (try? c.decode([EcoDevice].self, forKey: .ecosystem)) ?? []
        let root = (try? c.decode(String.self, forKey: .panelsRoot)) ?? ""
        panelsRoot = root.isEmpty ? nil : root
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(menuBar, forKey: .menuBar)
        try c.encode(alerts, forKey: .alerts)
        try c.encode(lifecycle, forKey: .lifecycle)
        try c.encode(deviceAlerts, forKey: .deviceAlerts)
        try c.encode(hiddenDevices, forKey: .hiddenDevices)
        try c.encode(chargeLimit, forKey: .chargeLimit)
        try c.encode(glowIntensity, forKey: .glowIntensity)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encode(autoDismissMacAlerts, forKey: .autoDismissMacAlerts)
        try c.encode(quietHours, forKey: .quietHours)
        try c.encode(ecosystem, forKey: .ecosystem)
        try c.encodeIfPresent(panelsRoot, forKey: .panelsRoot)
    }

    // MARK: Persistence
    static let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("Zest", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    static var fileURL: URL { dir.appendingPathComponent("config.json") }

    static func load() -> AppConfig {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            let fresh = AppConfig(); fresh.save(); return fresh
        }
        if let data = try? Data(contentsOf: fileURL),
           let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) {
            return cfg
        }
        // The file exists but does not decode (partial write, hand edit). Keep it
        // for the user instead of overwriting every alert and device with defaults.
        let bad = fileURL.appendingPathExtension("bad")
        try? fm.removeItem(at: bad)
        try? fm.moveItem(at: fileURL, to: bad)
        let fresh = AppConfig(); fresh.save(); return fresh
    }

    func save() {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
        // .atomic: a crash mid-write can no longer leave a truncated config.
        if let data = try? enc.encode(self) { try? data.write(to: AppConfig.fileURL, options: .atomic) }
    }
}
