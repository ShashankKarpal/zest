import Foundation
import Combine

// Runs one ported widget's data pipeline. The pipeline is the EXACT shell command from
// the original Ubersicht widget, extracted byte-for-byte by panels/extract-panels.py into
// a script inside the folder the user names in Settings (config `panelsRoot`). Running
// the original command verbatim preserves behavior exactly: same ccusage wrappers, same
// jq filters, same plist reads, same /tmp caches, same fallbacks. This app never rewrites
// those. With no `panelsRoot` configured the runner is inert: nothing is spawned, ever.
final class WidgetPanelRunner: ObservableObject {
    @Published private(set) var json: [String: Any] = [:]
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var raw: String = ""

    let scriptName: String
    let interval: TimeInterval
    private(set) var scriptPath: String?
    private var timer: Timer?
    private var started = false

    init(scriptName: String, interval: TimeInterval, root: String?) {
        self.scriptName = scriptName
        self.interval = interval
        self.scriptPath = WidgetPanelRunner.resolve(root: root, scriptName: scriptName)
    }

    var isConfigured: Bool { scriptPath != nil }

    private static func resolve(root: String?, scriptName: String) -> String? {
        guard let root, !root.isEmpty else { return nil }
        let expanded = NSString(string: root).expandingTildeInPath
        return (expanded as NSString).appendingPathComponent(scriptName)
    }

    // Point the runner at a different folder (or nil to switch it off). Takes effect at
    // once: a running timer is restarted against the new path, or stopped.
    func reconfigure(root: String?) {
        scriptPath = WidgetPanelRunner.resolve(root: root, scriptName: scriptName)
        json = [:]; raw = ""; lastUpdated = nil
        if started { stop(); started = false; start() }
    }

    func start() {
        guard !started else { return }
        started = true
        guard scriptPath != nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
    }
    func stop() { timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate() }

    func refresh() {
        guard let path = scriptPath else { return }
        // Only a regular file is worth a bash spawn; a missing or moved folder stays silent
        // instead of failing four times a cycle.
        guard FileManager.default.isReadableFile(atPath: path) else {
            DispatchQueue.main.async { self.raw = "Panel script not found: \(path)" }
            return
        }
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
