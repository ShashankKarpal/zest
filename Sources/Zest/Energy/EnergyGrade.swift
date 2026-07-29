import SwiftUI

// Single source of truth for the green / yellow / red energy classification, so every view
// grades the same way. Unit is CPU time per second (ms/s); 1000 ms/s is one full core busy.
// These are reasoned defaults (Apple's own energy-impact formula is private and also weighs
// GPU, wakeups, disk, and network); tune the constants here and the whole app follows.
enum EnergyGrade {
    case green, yellow, red

    var color: Color {
        switch self { case .green: return Theme.green; case .yellow: return Theme.orange; case .red: return Theme.red }
    }
    var label: String {
        switch self { case .green: return "Efficient"; case .yellow: return "Elevated"; case .red: return "High" }
    }
    var appLabel: String {
        switch self { case .green: return "efficient"; case .yellow: return "elevated"; case .red: return "high" }
    }

    // Per-app thresholds in ms/s.
    static let appYellow: Double = 100      // ~10% of one core
    static let appRed: Double = 600         // ~60% of one core sustained
    static let appRedMisbehaving: Double = 300  // lower bar when above the app's own baseline

    static func app(_ msPerS: Double, misbehaving: Bool = false) -> EnergyGrade {
        if msPerS >= appRed || (msPerS >= appRedMisbehaving && misbehaving) { return .red }
        if msPerS >= appYellow { return .yellow }
        return .green
    }

    // Whole-system: real drain in watts when on battery, total CPU load when on adapter.
    static let sysBatteryYellowW: Double = 10
    static let sysBatteryRedW: Double = 22
    static let sysAdapterYellowMs: Double = 2500
    static let sysAdapterRedMs: Double = 6000

    static func system(onBattery: Bool, drainWatts: Double, totalMsPerS: Double) -> EnergyGrade {
        if onBattery {
            if drainWatts >= sysBatteryRedW { return .red }
            if drainWatts >= sysBatteryYellowW { return .yellow }
            return .green
        } else {
            if totalMsPerS >= sysAdapterRedMs { return .red }
            if totalMsPerS >= sysAdapterYellowMs { return .yellow }
            return .green
        }
    }
}
