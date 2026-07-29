import SwiftUI

// Shared Claude model color/label mapping, matching the widgets' MODEL_META.
enum ModelMeta {
    struct Info { let label: String; let color: Color }
    static let map: [String: Info] = [
        "fable":  Info(label: "Fable 5",  color: Color(hex: 0xEC4899)),
        "opus":   Info(label: "Opus 4.8", color: Color(hex: 0xF59E0B)),
        "opus48": Info(label: "Opus 4.8", color: Color(hex: 0xF59E0B)),
        "haiku":  Info(label: "Haiku",    color: Color(hex: 0x2DD4BF)),
        "sonnet": Info(label: "Sonnet",   color: Color(hex: 0x3B82F6)),
        "other":  Info(label: "Other",    color: Color(hex: 0x8E8E93))
    ]
    static let order = ["fable", "opus", "haiku", "sonnet", "other"]

    static func norm(_ m: String) -> String {
        if m == "opus48" { return "opus" }
        return map[m] != nil ? m : "other"
    }
    // ccusage model id -> family key
    static func family(_ id: String) -> String {
        let s = id.lowercased()
        if s.contains("fable") || s.contains("mythos") { return "fable" }
        if s.contains("opus") { return "opus" }
        if s.contains("haiku") { return "haiku" }
        if s.contains("sonnet") { return "sonnet" }
        return "other"
    }
    static func info(_ key: String) -> Info { map[key] ?? map["other"]! }
    // Pretty label for a raw ccusage model id (Account 2 style).
    static func ccLabel(_ id: String) -> String {
        var parts = id.replacingOccurrences(of: "claude-", with: "").split(separator: "-").map(String.init)
        guard !parts.isEmpty else { return "Other" }
        var fam = parts.removeFirst()
        fam = fam.prefix(1).uppercased() + fam.dropFirst()
        let ver = parts.filter { $0.allSatisfy(\.isNumber) && $0.count <= 2 }.joined(separator: ".")
        return ver.isEmpty ? fam : "\(fam) \(ver)"
    }
}

// Time helpers matching the widgets' countdown/clockTime.
enum TimeFmt {
    static let cocoa: Double = 978307200
    static func countdown(_ target: Date, _ now: Date = Date()) -> String {
        let ms = target.timeIntervalSince(now)
        if ms <= 0 { return "resetting" }
        let min = Int(ms / 60)
        let h = min / 60, m = min % 60
        if h >= 24 { return "\(h/24)d \(h%24)h" }
        return "\(h)h\(String(format: "%02d", m))m"
    }
    static func clock(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE h:mm a"
        return f.string(from: d)
    }
    static func fromCocoa(_ secs: Double) -> Date { Date(timeIntervalSince1970: secs + cocoa) }
}
