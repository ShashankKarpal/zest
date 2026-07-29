import Foundation
import Combine

// Produces a short, plain-language battery digest using the local LM Studio model
// (qwen3-14b-mlx at localhost:1234). Everything stays on the machine; if LM Studio is not
// running, it falls back to a locally-composed summary so the feature still works.
//
// It also surfaces a local "late-night high-drain" signal from Zest's own energy history.
// The deeper correlation with HRV and sleep lives in the Claude health copilot (which has
// the Whoop and Apple Health data); this app only nudges from what it can see locally.
final class DigestService: ObservableObject {
    @Published private(set) var digest = ""
    @Published private(set) var busy = false
    @Published private(set) var usedLocalModel = false

    private let battery: BatteryService
    private let history: BatteryHistory
    private let energy: EnergySampler

    private let endpoint = URL(string: "http://localhost:1234/v1/chat/completions")!
    private let model = "qwen3-14b-mlx"

    init(battery: BatteryService, history: BatteryHistory, energy: EnergySampler) {
        self.battery = battery
        self.history = history
        self.energy = energy
    }

    // Detects hours between 23:00 and 04:00 with above-average energy in the last 7 days.
    func lateNightHighDrain() -> String? {
        let hot = energy.window.last7d.prefix(3).map { $0.name }
        guard !hot.isEmpty else { return nil }
        let cal = Calendar.current
        let hour = cal.component(.hour, from: Date())
        let isLate = hour >= 23 || hour < 4
        if isLate && (energy.window.live.first?.value ?? 0) > 200 {
            return "It is late and the Mac is working hard (\(energy.window.live.first?.name ?? "an app") is busy). A wind-down would help sleep and HRV."
        }
        return nil
    }

    private func statsSummary() -> String {
        let s = battery.snapshot
        var lines: [String] = []
        lines.append("Charge: \(s.percent)%, \(s.isCharging ? "charging" : (s.isACPower ? "on adapter" : "on battery")).")
        if let c = s.maxCapacityPercent, let cy = s.cycleCount { lines.append("Health: \(c)% capacity, \(cy) cycles, \(s.condition ?? "").") }
        if let t = s.temperatureC { lines.append("Temperature: \(String(format: "%.1f", t)) C.") }
        lines.append("System draw: \(String(format: "%.1f", s.systemWatts)) W; adapter \(s.adapterWatts.map { "\($0) W" } ?? "n/a").")
        let top = energy.window.last24h.prefix(5).map { "\($0.name) \(Int($0.value)) ms/s" }.joined(separator: ", ")
        if !top.isEmpty { lines.append("Top energy apps (24h avg): \(top).") }
        if let ln = lateNightHighDrain() { lines.append(ln) }
        return lines.joined(separator: "\n")
    }

    func generate() {
        guard !busy else { return }
        busy = true
        let stats = statsSummary()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.callLMStudio(stats: stats)
            DispatchQueue.main.async {
                self.digest = result.text
                self.usedLocalModel = result.local
                self.busy = false
            }
        }
    }

    private func callLMStudio(stats: String) -> (text: String, local: Bool) {
        let prompt = """
        /no_think
        You are a concise battery assistant. Given these Mac battery stats, write 2 to 4 short sentences of plain, useful observations and one practical tip. Do not use em dashes. Do not invent numbers beyond what is given.

        \(stats)
        """
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.4,
            "max_tokens": 220,
            "stream": false
        ]
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 30

        let sem = DispatchSemaphore(value: 0)
        var out: String?
        let task = URLSession.shared.dataTask(with: req) { data, _, _ in
            defer { sem.signal() }
            guard let data = data else { return }
            // LM Studio can emit literal control characters inside the JSON string (Qwen3's
            // reasoning block), which is invalid JSON. Replace control bytes with spaces so
            // the payload parses; the digest content is unaffected.
            let sanitized = Data(data.map { $0 < 0x20 ? 0x20 : $0 })
            guard let obj = try? JSONSerialization.jsonObject(with: sanitized) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let msg = choices.first?["message"] as? [String: Any],
                  var content = msg["content"] as? String else { return }
            // Strip any <think> block the model emits.
            if let r = content.range(of: "</think>") { content = String(content[r.upperBound...]) }
            out = content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 32)

        if let out = out, !out.isEmpty { return (out, true) }
        // Fallback: local summary, no model.
        return ("LM Studio was not reachable, so here is the raw local summary:\n\n\(stats)", false)
    }
}
