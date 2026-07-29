import Foundation
import Combine

// Runs one ported widget's data pipeline. The pipeline is the EXACT shell command from
// the original Ubersicht widget, extracted byte-for-byte into a script under
// ~/Projects/zest/panels/ at install time (see sync-panels.sh). Running the original
// command verbatim preserves behavior exactly: same ccusage wrappers, same jq filters,
// same plist reads, same /tmp caches, same fallbacks. This app never rewrites those.
final class WidgetPanelRunner: ObservableObject {
    @Published private(set) var json: [String: Any] = [:]
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var raw: String = ""

    let scriptPath: String
    let interval: TimeInterval
    private var timer: Timer?

    init(scriptName: String, interval: TimeInterval) {
        self.scriptPath = NSString(string: "~/Projects/zest/panels/\(scriptName)").expandingTildeInPath
        self.interval = interval
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
    }
    func stop() { timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate() }

    func refresh() {
        let path = scriptPath
        DispatchQueue.global(qos: .utility).async {
            let out = Shell.run("/bin/bash \(self.q(path))", timeout: 30)
            let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { self.raw = trimmed }
                return
            }
            DispatchQueue.main.async {
                self.json = obj
                self.raw = trimmed
                self.lastUpdated = Date()
            }
        }
    }

    private func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

// Lightweight, defensive accessor over a parsed JSON dictionary. Mirrors the widgets'
// "|| 0" / "// 0" tolerance for missing fields.
struct JDict {
    let dict: [String: Any]
    init(_ d: [String: Any]) { dict = d }
    init(_ any: Any?) { dict = (any as? [String: Any]) ?? [:] }

    subscript(_ key: String) -> Any? { dict[key] }
    func obj(_ key: String) -> JDict { JDict(dict[key] as? [String: Any] ?? [:]) }
    func arr(_ key: String) -> [Any] { dict[key] as? [Any] ?? [] }
    func objArr(_ key: String) -> [JDict] { arr(key).compactMap { ($0 as? [String: Any]).map(JDict.init) } }

    func d(_ key: String, _ def: Double = 0) -> Double {
        if let n = dict[key] as? Double { return n }
        if let n = dict[key] as? Int { return Double(n) }
        if let n = dict[key] as? NSNumber { return n.doubleValue }
        if let s = dict[key] as? String, let n = Double(s) { return n }
        return def
    }
    func i(_ key: String, _ def: Int = 0) -> Int { Int(d(key, Double(def)).rounded()) }
    func s(_ key: String, _ def: String = "") -> String { (dict[key] as? String) ?? def }
    func b(_ key: String, _ def: Bool = false) -> Bool { (dict[key] as? Bool) ?? def }
    func has(_ key: String) -> Bool { dict[key] != nil }
    var isEmpty: Bool { dict.isEmpty }
}
