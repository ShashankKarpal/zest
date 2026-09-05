import Foundation
import Combine
import AppKit

// Fired alert payload the overlay manager renders.
struct AlertPayload {
    var title: String
    var subtitle: String
    var colorHex: UInt32
    var glow: Bool
    var persistent: Bool
    var sound: String
    var position: PillPosition
    var symbol: String   // SF Symbol name
}

// Evaluates battery, lifecycle, and device rules on every battery/device change.
// Uses per-rule hysteresis so an alert fires once per crossing, not repeatedly.
final class AlertEngine {
    private let config: AppConfig
    private let overlay: OverlayManager
    private let history: AlertHistory?

    private var lastPercent: Int?
    private var lastAC: Bool?
    private var lastCharging: Bool?
    private var lastFull: Bool?
    private var crossed = Set<UUID>()          // battery rules already fired this crossing
    private var lifecycleArmed = true
    private var deviceCrossed = Set<String>()  // "name:low" / "name:full" fired

    init(config: AppConfig, overlay: OverlayManager, history: AlertHistory? = nil) {
        self.config = config
        self.overlay = overlay
        self.history = history
    }

    // Central gate: suppresses alerts during quiet hours, except a critical low-battery
    // alert when "allow critical" is on. Everything routes through here.
    private func present(_ payload: AlertPayload, critical: Bool) {
        let hour = Calendar.current.component(.hour, from: Date())
        var suppressed = false
        if config.quietHours.contains(hour: hour) {
            if !(critical && config.quietHours.allowCritical) { suppressed = true }
        }
        history?.record(title: payload.title, subtitle: payload.subtitle, colorHex: payload.colorHex, suppressed: suppressed)
        if suppressed { return }
        overlay.show(payload)
    }

    // MARK: Battery + lifecycle
    func evaluateBattery(_ snap: BatterySnapshot) {
        defer {
            lastPercent = snap.percent
            lastAC = snap.isACPower
            lastCharging = snap.isCharging
            lastFull = snap.fullyCharged
        }
        let p = snap.percent

        // Battery threshold rules
        for rule in config.alerts where rule.enabled {
            switch rule.direction {
            case .falling:
                if p <= rule.threshold {
                    if !crossed.contains(rule.id) {
                        crossed.insert(rule.id)
                        fireBattery(rule, snap: snap)
                    }
                } else if p > rule.threshold + 1 {
                    crossed.remove(rule.id)   // re-arm once clearly back above
                }
            case .rising:
                if p >= rule.threshold {
                    if !crossed.contains(rule.id) {
                        crossed.insert(rule.id)
                        fireBattery(rule, snap: snap)
                    }
                } else if p < rule.threshold - 1 {
                    crossed.remove(rule.id)
                }
            }
        }

        // Lifecycle transitions
        if let wasAC = lastAC {
            if !wasAC && snap.isACPower { fireLifecycle(.pluggedIn) }
            if wasAC && !snap.isACPower { fireLifecycle(.unpluggedFrom) }
        }
        if let wasP = lastPercent, wasP < 80 && p >= 80 { fireLifecycle(.chargedAbove80) }
        if let wasFull = lastFull, !wasFull && snap.fullyCharged { fireLifecycle(.fullyCharged) }
    }

    private func fireBattery(_ rule: BatteryAlertRule, snap: BatterySnapshot) {
        let dir = rule.direction == .falling ? "dropped to" : "reached"
        let sub: String
        if rule.direction == .falling, let m = snap.timeRemainingMinutes, !snap.timeIsToFull {
            sub = "About \(m/60)h \(m%60)m of battery left"
        } else if rule.direction == .rising {
            sub = snap.isACPower ? "Unplug to protect long-term battery health" : "Battery is topping up"
        } else {
            sub = "Consider plugging in soon"
        }
        let critical = rule.direction == .falling && rule.threshold <= config.quietHours.criticalPercent
        present(AlertPayload(
            title: "Battery \(dir) \(rule.threshold)%",
            subtitle: sub,
            colorHex: rule.colorHex,
            glow: rule.glow,
            persistent: rule.persistent,
            sound: rule.sound,
            position: rule.position,
            symbol: rule.direction == .falling ? "battery.25" : "battery.100.bolt"
        ), critical: critical)
    }

    private func fireLifecycle(_ event: LifecycleEvent) {
        guard let rule = config.lifecycle.first(where: { $0.event == event && $0.enabled }) else { return }
        let meta: (String, String, UInt32, String) = {
            switch event {
            case .pluggedIn: return ("Charger connected", "Power adapter plugged in", 0x32D74B, "powerplug")
            case .unpluggedFrom: return ("Running on battery", "Charger disconnected", 0xF59E0B, "bolt.slash")
            case .chargedAbove80: return ("Charged to 80%", "Unplug now to maximize battery lifespan", 0x32D74B, "leaf")
            case .fullyCharged: return ("Fully charged", "Battery at 100%", 0x3B82F6, "battery.100")
            }
        }()
        present(AlertPayload(
            title: meta.0, subtitle: meta.1, colorHex: meta.2,
            glow: rule.glow, persistent: rule.persistent, sound: rule.sound,
            position: .topRight, symbol: meta.3
        ), critical: false)
    }

    // MARK: Device alerts
    func evaluateDevices(_ devices: [AuxDevice]) {
        for dev in devices {
            guard let rule = config.deviceAlerts.first(where: { $0.deviceName == dev.name }) else { continue }
            let level = dev.sortLevel
            let lowKey = "\(dev.name):low"
            let fullKey = "\(dev.name):full"
            if rule.lowEnabled && level <= rule.lowThreshold {
                if !deviceCrossed.contains(lowKey) {
                    deviceCrossed.insert(lowKey)
                    present(AlertPayload(
                        title: "\(dev.name) at \(level)%",
                        subtitle: "Charge your \(dev.name) soon",
                        colorHex: rule.colorHex, glow: false, persistent: false,
                        sound: rule.sound, position: .topRight, symbol: "battery.25"), critical: false)
                }
            } else if level > rule.lowThreshold + 3 { deviceCrossed.remove(lowKey) }

            if rule.fullEnabled && level >= 100 {
                if !deviceCrossed.contains(fullKey) {
                    deviceCrossed.insert(fullKey)
                    present(AlertPayload(
                        title: "\(dev.name) fully charged",
                        subtitle: "\(dev.name) reached 100%",
                        colorHex: 0x32D74B, glow: false, persistent: false,
                        sound: rule.sound, position: .topRight, symbol: "battery.100"), critical: false)
                }
            } else if level < 98 { deviceCrossed.remove(fullKey) }
        }
    }
}
