import SwiftUI

// Dark glassmorphism theme lifted from the existing Ubersicht widget dashboard so the
// new app matches Account 1, Account 2, System Vitals, and the Claude Code widget.
enum Theme {
    // Surfaces
    static let cardBG = Color(red: 15/255, green: 15/255, blue: 18/255).opacity(0.92)
    static let panelBG = Color(red: 20/255, green: 20/255, blue: 20/255)      // #141414 (vitals)
    static let tileBG = Color.white.opacity(0.03)
    static let cardBorder = Color.white.opacity(0.08)
    static let hairline = Color.white.opacity(0.06)

    // Text
    static let text = Color.white
    static let textVitals = Color(red: 229/255, green: 231/255, blue: 235/255) // #E5E7EB
    static let dim = Color.white.opacity(0.5)
    static let faint = Color.white.opacity(0.4)
    static let ghost = Color.white.opacity(0.35)

    // Accents (union of the widgets' palettes)
    static let green = Color(hex: 0x32D74B)
    static let green2 = Color(hex: 0x4ADE80)
    static let emerald = Color(hex: 0x10B981)
    static let amber = Color(hex: 0xF59E0B)
    static let orange = Color(hex: 0xF97316)
    static let red = Color(hex: 0xEF4444)
    static let redSoft = Color(hex: 0xF87171)
    static let blue = Color(hex: 0x3B82F6)
    static let sky = Color(hex: 0x0A84FF)
    static let purple = Color(hex: 0xA78BFA)
    static let pink = Color(hex: 0xEC4899)
    static let teal = Color(hex: 0x2DD4BF)

    static let font = "SF Pro Display"

    // Battery level color ramp used across the widgets.
    static func batteryColor(_ p: Double) -> Color {
        if p >= 60 { return green }
        if p >= 30 { return amber }
        if p >= 15 { return redSoft }
        return red
    }

    static func gaugeColor(_ p: Double, warn: Double = 60, crit: Double = 85) -> Color {
        if p >= crit { return red }
        if p >= warn { return orange }
        return green
    }
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

// Shared number formatters matching the widgets' fmt() helpers.
enum Fmt {
    static func tokens(_ n: Double) -> String {
        if n >= 1_000_000 { return String(format: "%.2fM", n / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", n / 1_000) }
        return "\(Int(n.rounded()))"
    }
    static func money(_ n: Double) -> String { String(format: "$%.2f", n) }
    static func pct(_ n: Double) -> String { "\(Int(n.rounded()))%" }
}
