import Foundation
import AppKit

// Exports Zest's local history to CSV/JSON and writes a weekly markdown report. Everything
// stays on disk in the app's own folder (no TCC prompt); a Reveal in Finder button opens it.
final class ExportService {
    let history: BatteryHistory
    let energy: EnergySampler
    let battery: BatteryService

    init(history: BatteryHistory, energy: EnergySampler, battery: BatteryService) {
        self.history = history
        self.energy = energy
        self.battery = battery
    }

    static let dir: URL = {
        let d = AppConfig.dir.appendingPathComponent("exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private func stamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f.string(from: Date())
    }

    @discardableResult
    func exportBatteryHealthCSV() -> URL {
        var lines = ["day,max_capacity_percent,cycles,temp_c"]
        for s in history.samples {
            lines.append("\(s.day),\(s.maxCapacity.map(String.init) ?? ""),\(s.cycles.map(String.init) ?? ""),\(s.tempC.map { String(format: "%.2f", $0) } ?? "")")
        }
        let url = ExportService.dir.appendingPathComponent("battery-health-\(stamp()).csv")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    func exportEnergyCSV() -> URL {
        var lines = ["window,app,value_ms_per_s"]
        func add(_ w: String, _ items: [EnergySampler.AppEnergy]) {
            for a in items { lines.append("\(w),\(a.name),\(String(format: "%.2f", a.value))") }
        }
        add("live", energy.window.live)
        add("24h", energy.window.last24h)
        add("7d", energy.window.last7d)
        add("30d", energy.window.last30d)
        let url = ExportService.dir.appendingPathComponent("energy-\(stamp()).csv")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    func exportJSON() -> URL {
        let snap = battery.snapshot
        let payload: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "battery": [
                "percent": snap.percent,
                "maxCapacityPercent": snap.maxCapacityPercent as Any,
                "cycleCount": snap.cycleCount as Any,
                "temperatureC": snap.temperatureC as Any,
                "condition": snap.condition as Any
            ],
            "healthHistory": history.samples.map { ["day": $0.day, "maxCapacity": $0.maxCapacity as Any, "cycles": $0.cycles as Any, "tempC": $0.tempC as Any] },
            "energy24h": energy.window.last24h.map { ["app": $0.name, "msPerS": $0.value] }
        ]
        let url = ExportService.dir.appendingPathComponent("zest-export-\(stamp()).json")
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
            try? data.write(to: url)
        }
        return url
    }

    // Weekly markdown report. No em dashes anywhere in the output.
    @discardableResult
    func writeWeeklyReport() -> URL {
        let snap = battery.snapshot
        let proj = history.projection
        let df = DateFormatter(); df.dateFormat = "yyyy-'W'ww"
        let week = df.string(from: Date())
        var md = "# Zest weekly battery report (\(week))\n\n"
        md += "Generated \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))\n\n"
        md += "## Battery health\n\n"
        md += "Max capacity: \(snap.maxCapacityPercent.map { "\($0)%" } ?? "n/a"). "
        md += "Cycle count: \(snap.cycleCount.map(String.init) ?? "n/a"). "
        md += "Condition: \(snap.condition ?? "n/a").\n\n"
        if let pm = proj.perMonthCycles { md += "Estimated cycles per month: \(String(format: "%.0f", pm)).\n" }
        if let m = proj.monthsTo80 { md += "Projected time to 80% capacity: about \(m) months at the current trend.\n" }
        md += "\n## Top energy use, last 7 days (avg ms/s)\n\n"
        if energy.window.last7d.isEmpty {
            md += "Not enough history collected yet.\n"
        } else {
            for a in energy.window.last7d.prefix(8) { md += "- \(a.name): \(String(format: "%.1f", a.value)) ms/s\n" }
        }
        md += "\n## Notes\n\n"
        md += "Battery care is managed by macOS. Data is local to this Mac.\n"
        let url = ExportService.dir.appendingPathComponent("weekly-\(week).md")
        try? md.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func revealInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: ExportService.dir.path)
    }
}
