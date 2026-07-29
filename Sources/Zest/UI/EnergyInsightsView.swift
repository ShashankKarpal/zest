import SwiftUI

// Per-app energy insights. Unit is CPU time per second, milliseconds per second (ms/s).
// Live is the latest sample; 24h/7d/30d are averages over the history actually collected
// since the app was first run, with an honest note about how much history exists.
struct EnergyInsightsView: View {
    @ObservedObject var energy: EnergySampler
    @ObservedObject var battery: BatteryService
    @State private var window: Int = 0   // 0 live, 1 24h, 2 7d, 3 30d

    var body: some View {
        let w = energy.window
        let snap = battery.snapshot
        let sysGrade = EnergyGrade.system(onBattery: !snap.isACPower,
                                          drainWatts: abs(min(0, snap.batteryWatts)),
                                          totalMsPerS: w.totalLive)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHead(label: "ENERGY USE BY APP")
                Spacer()
                Picker("", selection: $window) {
                    Text("Live").tag(0); Text("24h").tag(1); Text("7d").tag(2); Text("30d").tag(3)
                }.pickerStyle(.segmented).frame(width: 220)
            }

            HStack(spacing: 8) {
                Text("SYSTEM ENERGY").font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundColor(Theme.faint)
                Badge(text: sysGrade.label, color: sysGrade.color)
                Text(snap.isACPower ? "\(Int(w.totalLive.rounded())) ms/s total on adapter"
                                    : String(format: "%.1f W drain on battery", abs(min(0, snap.batteryWatts))))
                    .font(.system(size: 10)).foregroundColor(Theme.dim)
            }

            // Honest data-span note for the historical windows.
            if window != 0 {
                Text(spanNote(w))
                    .font(.system(size: 10)).foregroundColor(coversWindow(w) ? Theme.dim : Theme.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if window == 1 || window == 0 {
                Sparkline(values: w.spark24h, color: Theme.teal).frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.tileBG))
                Text("Average ms/s per hour, last 24 hours").font(.system(size: 9)).foregroundColor(Theme.faint)
            }

            let list = current(w)
            let unit = window == 0 ? "ms/s" : "avg ms/s"
            if list.isEmpty {
                Text("Collecting samples. Energy history begins when Zest starts running.")
                    .font(.system(size: 11)).foregroundColor(Theme.faint)
            }
            let maxV = max(0.1, list.map { $0.value }.max() ?? 0.1)
            ForEach(list) { app in
                let grade = EnergyGrade.app(app.value, misbehaving: app.isMisbehaving)
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(grade.color).frame(width: 6, height: 6)
                        Text(app.name).font(.system(size: 11)).foregroundColor(Theme.text).lineLimit(1)
                        if app.isMisbehaving {
                            Text("misbehaving").font(.system(size: 9, weight: .semibold)).foregroundColor(Theme.orange)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3).fill(Theme.orange.opacity(0.15)))
                        }
                        Spacer()
                        Text("\(fmt(app.value)) \(unit)").font(.system(size: 11, weight: .semibold)).foregroundColor(grade.color)
                    }
                    MeterBar(pct: app.value / maxV * 100, color: grade.color, height: 5)
                }
            }

            HStack(spacing: 12) {
                LegendDot(color: Theme.green, label: "Efficient", value: "<100")
                LegendDot(color: Theme.orange, label: "Elevated", value: "100-600")
                LegendDot(color: Theme.red, label: "High", value: ">600")
            }
            Text("ms/s per app; 1000 ms/s is one full CPU core. Red also triggers when an app runs well above its own recent baseline.")
                .font(.system(size: 9)).foregroundColor(Theme.ghost).fixedSize(horizontal: false, vertical: true)

            Text(energy.usingPowermetrics
                 ? "Unit: CPU ms/s per app, from powermetrics. Milliseconds of CPU time used per second. Computed locally; higher means more battery drain."
                 : "Unit: CPU %-share proxy per app (ps). Grant the powermetrics sudoers line for true powermetrics ms/s. Computed locally.")
                .font(.system(size: 9)).foregroundColor(Theme.ghost).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fmt(_ v: Double) -> String { v >= 100 ? "\(Int(v.rounded()))" : String(format: "%.1f", v) }

    private func current(_ w: EnergySampler.Window) -> [EnergySampler.AppEnergy] {
        switch window { case 0: return w.live; case 1: return w.last24h; case 2: return w.last7d; default: return w.last30d }
    }

    private func windowHours() -> Double { switch window { case 1: return 24; case 2: return 24*7; default: return 24*30 } }
    private func coversWindow(_ w: EnergySampler.Window) -> Bool { w.spanHours >= windowHours() * 0.9 }

    private func spanNote(_ w: EnergySampler.Window) -> String {
        guard let start = w.startedAt else { return "No history yet." }
        let f = DateFormatter(); f.dateFormat = "MMM d, HH:mm"
        let span = w.spanHours
        let spanStr = span < 1 ? String(format: "%.0f min", span * 60)
                    : span < 48 ? String(format: "%.1f h", span)
                    : String(format: "%.1f days", span / 24)
        if coversWindow(w) {
            return "History collected since \(f.string(from: start)) (\(spanStr))."
        }
        return "Only \(spanStr) of history so far (since \(f.string(from: start))). Showing everything collected; the full window fills in as Zest keeps running."
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let maxV = max(0.001, values.max() ?? 0.001)
            let step = values.count > 1 ? geo.size.width / CGFloat(values.count - 1) : geo.size.width
            Path { p in
                for (i, v) in values.enumerated() {
                    let x = CGFloat(i) * step
                    let y = geo.size.height * (1 - CGFloat(v / maxV))
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
    }
}
