import Foundation

// Snapshot of everything Zest knows about the internal Mac battery at one instant.
struct BatterySnapshot: Equatable {
    var percent: Int = 0
    var isCharging: Bool = false
    var isACPower: Bool = false
    var fullyCharged: Bool = false
    var timeRemainingMinutes: Int? = nil     // to empty (on battery) or to full (charging)
    var timeIsToFull: Bool = false

    // Detail (ioreg AppleSmartBattery)
    var temperatureC: Double? = nil
    var voltageV: Double? = nil
    var amperageMA: Int? = nil               // signed, negative = discharging
    var designCapacityMAh: Int? = nil
    var rawMaxCapacityMAh: Int? = nil

    // Adapter
    var adapterWatts: Int? = nil
    var adapterName: String? = nil
    var adapterVoltage: Double? = nil        // volts
    var adapterCurrentMA: Int? = nil

    // Health (cycles and capacity from the IORegistry; condition from system_profiler, hourly)
    var cycleCount: Int? = nil
    var maxCapacityPercent: Int? = nil
    var condition: String? = nil

    // System thermal pressure (ProcessInfo.thermalState), free to read, pushed on change.
    var thermalState: ProcessInfo.ThermalState = .nominal
    var thermalLabel: String { Self.thermalLabel(thermalState) }
    var thermalIsElevated: Bool { thermalState != .nominal }
    static func thermalLabel(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    // Derived power (watts)
    var batteryWatts: Double {
        guard let v = voltageV, let a = amperageMA else { return 0 }
        return v * (Double(a) / 1000.0)
    }
    var batteryPowerState: String {
        let w = batteryWatts
        if w > 1 { return "charging" }
        if w < -0.5 { return "discharging" }
        return "idle"
    }
    // Wattage the system itself is consuming.
    var systemWatts: Double {
        if isACPower, let aw = adapterWatts {
            // system = adapter output minus what is going into the battery
            let toBattery = max(0, batteryWatts)
            return max(0, Double(aw) - toBattery)
        } else {
            // on battery: system draw equals battery discharge
            return abs(min(0, batteryWatts))
        }
    }
    var adapterUnderpowered: Bool {
        guard isACPower, let aw = adapterWatts else { return false }
        return systemWatts > Double(aw) + 2 || (isACPower && batteryWatts < -0.5)
    }
    var serviceRecommended: Bool {
        if let c = condition, c.lowercased().contains("service") { return true }
        if let m = maxCapacityPercent, m < 80 { return true }
        return false
    }
}

// One connected auxiliary device (AirPods, mouse, keyboard, iPhone, etc.)
struct AuxDevice: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var battery: Int?        // single-cell
    var left: Int?           // stereo
    var right: Int?
    var caseLevel: Int?
    var source: String       // bt / hid / ble
    var isStereo: Bool { left != nil || right != nil || caseLevel != nil }
    var sortLevel: Int { battery ?? [left, right, caseLevel].compactMap { $0 }.min() ?? 100 }
}
