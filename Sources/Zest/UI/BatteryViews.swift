import SwiftUI

// Native battery views: health card, device leaderboard, charge-limit controls.

struct BatteryHealthView: View {
    let snap: BatterySnapshot
    var history: BatteryHistory? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHead(label: "BATTERY HEALTH")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                Tile(label: "MAX CAPACITY", value: snap.maxCapacityPercent.map { "\($0)%" } ?? "--",
                     color: capColor(snap.maxCapacityPercent))
                Tile(label: "CYCLES", value: snap.cycleCount.map { "\($0)" } ?? "--")
                Tile(label: "TEMP", value: snap.temperatureC.map { String(format: "%.1f°C", $0) } ?? "--",
                     color: (snap.temperatureC ?? 0) >= 35 ? Theme.orange : Theme.text)
                Tile(label: "CONDITION", value: snap.condition ?? "--",
                     color: (snap.condition == "Normal") ? Theme.green : Theme.orange)
            }
            HStack(spacing: 16) {
                metric("Voltage", snap.voltageV.map { String(format: "%.2f V", $0) } ?? "--")
                metric("Design", snap.designCapacityMAh.map { "\($0) mAh" } ?? "--")
                metric("Full", snap.rawMaxCapacityMAh.map { "\($0) mAh" } ?? "--")
            }
            if snap.serviceRecommended {
                Text("⚠︎ Service recommended. Consider a battery check with Apple Support.")
                    .font(.system(size: 10)).foregroundColor(Theme.orange)
            }
            if let history { HealthTrend(history: history) }
        }
    }
    private func capColor(_ c: Int?) -> Color {
        guard let c else { return Theme.dim }
        if c >= 90 { return Theme.text }; if c >= 80 { return Theme.teal }; if c >= 70 { return Theme.orange }; return Theme.red
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.text)
            Text(label).font(.system(size: 9)).foregroundColor(Theme.faint)
        }.frame(maxWidth: .infinity)
    }
}

// Capacity trendline over time plus a simple degradation projection.
struct HealthTrend: View {
    @ObservedObject var history: BatteryHistory
    var body: some View {
        let caps = history.samples.compactMap { $0.maxCapacity }.map(Double.init)
        let proj = history.projection
        return VStack(alignment: .leading, spacing: 8) {
            SectionHead(label: "HEALTH TREND", right: "\(history.samples.count) days")
            if caps.count < 2 {
                Text("Collecting daily samples. The capacity trend appears after a couple of days.")
                    .font(.system(size: 10)).foregroundColor(Theme.ghost)
            } else {
                let lo = max(60, (caps.min() ?? 80) - 2)
                let hi = min(100, (caps.max() ?? 100) + 1)
                Sparkline(values: caps.map { ($0 - lo) / max(1, hi - lo) * 100 }, color: Theme.teal)
                    .frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.tileBG))
                HStack {
                    Text("Range \(Int(caps.first ?? 0))% to \(Int(caps.last ?? 0))%").font(.system(size: 10)).foregroundColor(Theme.dim)
                    Spacer()
                    if let pm = proj.perMonthCycles { Text(String(format: "~%.0f cycles/mo", pm)).font(.system(size: 10)).foregroundColor(Theme.dim) }
                    if let m = proj.monthsTo80 { Text("~\(m) mo to 80%").font(.system(size: 10)).foregroundColor(Theme.faint) }
                }
            }
        }
    }
}

struct DeviceLeaderboardView: View {
    let devices: [AuxDevice]
    let hidden: [String]
    var body: some View {
        let shown = devices.filter { !hidden.contains($0.name) }
        return VStack(alignment: .leading, spacing: 8) {
            SectionHead(label: "DEVICES", right: "\(shown.count)")
            if shown.isEmpty {
                Text("No auxiliary devices detected").font(.system(size: 11)).foregroundColor(Theme.faint)
            }
            ForEach(shown) { dev in DeviceLeaderRow(dev: dev) }
        }
    }
}

struct DeviceLeaderRow: View {
    let dev: AuxDevice
    var body: some View {
        if dev.isStereo {
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(icon(dev.name)); Text(dev.name).font(.system(size: 11)).foregroundColor(Theme.text) }
                HStack(spacing: 8) {
                    ForEach(cells(dev), id: \.0) { (label, v) in
                        VStack(spacing: 3) {
                            HStack { Text(label).font(.system(size: 10)).foregroundColor(Theme.dim); Spacer(); Text("\(v)%").font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.batteryColor(Double(v))) }
                            MeterBar(pct: Double(v), color: Theme.batteryColor(Double(v)), height: 4)
                        }
                    }
                }
            }.padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Theme.tileBG))
        } else {
            let pct = dev.battery ?? 0
            HStack(spacing: 10) {
                Text(icon(dev.name))
                VStack(alignment: .leading, spacing: 5) {
                    Text(dev.name).font(.system(size: 11)).foregroundColor(Theme.text).lineLimit(1)
                    MeterBar(pct: Double(pct), color: Theme.batteryColor(Double(pct)), height: 4)
                }
                Text(dev.battery != nil ? "\(pct)%" : "--").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.batteryColor(Double(pct))).frame(width: 42, alignment: .trailing)
            }.padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Theme.tileBG))
        }
    }
    private func cells(_ d: AuxDevice) -> [(String, Int)] {
        var out: [(String, Int)] = []
        if let l = d.left { out.append(("L", l)) }
        if let r = d.right { out.append(("R", r)) }
        if let c = d.caseLevel { out.append(("Case", c)) }
        return out
    }
    private func icon(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpod") || n.contains("beats") || n.contains("headphone") { return "🎧" }
        if n.contains("keyboard") { return "⌨️" }
        if n.contains("trackpad") { return "👆" }
        if n.contains("mouse") || n.contains("mx master") || n.contains("logi") { return "🖱️" }
        if n.contains("iphone") { return "📱" }
        if n.contains("ipad") { return "📲" }
        if n.contains("watch") { return "⌚" }
        return "🔗"
    }
}

struct ChargeLimitControls: View {
    @ObservedObject var config: AppConfig
    @ObservedObject var limiter: ChargeLimiter
    var onSave: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHead(label: "CHARGE LIMIT & CARE")
                Badge(text: "MACOS-MANAGED", color: Theme.blue)
            }
            Text("Managed by macOS (System Settings > Battery). Intentionally not enabled in Zest.")
                .font(.system(size: 11)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
            Button("Open macOS Battery settings") { limiter.openMacOSBatterySettings() }.font(.system(size: 11))
        }
    }
}
