import SwiftUI

// iPhone / iPad battery health over USB.
struct IOSHealthView: View {
    @ObservedObject var service: IOSDeviceService
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHead(label: "IPHONE & IPAD HEALTH", right: "over USB")
            Text(service.status).font(.system(size: 11)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
            ForEach(service.devices) { d in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(d.name).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                        if !d.product.isEmpty { Text(d.product).font(.system(size: 10)).foregroundColor(Theme.faint) }
                        Spacer()
                        if d.charging { Text("⚡ charging").font(.system(size: 10)).foregroundColor(Theme.teal) }
                    }
                    if let level = d.level {
                        HStack {
                            Text("Level").font(.system(size: 10)).foregroundColor(Theme.dim).frame(width: 80, alignment: .leading)
                            MeterBar(pct: Double(level), color: Theme.batteryColor(Double(level)), height: 6)
                            Text("\(level)%").font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.batteryColor(Double(level))).frame(width: 42, alignment: .trailing)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        Tile(label: "MAX CAPACITY", value: d.maxCapacity.map { "\($0)%" } ?? "n/a")
                        Tile(label: "CYCLES", value: d.cycleCount.map(String.init) ?? "n/a")
                    }
                    if d.cycleCount == nil && d.maxCapacity == nil {
                        Text("Deep health (cycles, capacity) needs the device unlocked and trusted. Level and charging state are always available.")
                            .font(.system(size: 9)).foregroundColor(Theme.ghost)
                    }
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Theme.tileBG))
            }
            Text("iOS battery health is only exposed over a cable, so macOS cannot read it wirelessly. This uses libimobiledevice and processes everything locally.")
                .font(.system(size: 9)).foregroundColor(Theme.ghost).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// Local battery digest from LM Studio (qwen3-14b-mlx), with a graceful local fallback.
struct DigestView: View {
    @ObservedObject var digest: DigestService
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHead(label: "BATTERY DIGEST", right: digest.usedLocalModel ? "qwen3-14b-mlx" : "local")
                Spacer()
                Button(digest.busy ? "Generating..." : "Generate") { digest.generate() }.disabled(digest.busy).font(.system(size: 11))
            }
            if let ln = digest.lateNightHighDrain() {
                Text("● \(ln)").font(.system(size: 11)).foregroundColor(Theme.orange).fixedSize(horizontal: false, vertical: true)
            }
            if digest.digest.isEmpty {
                Text("Generate a short, plain-language summary of today's battery and energy, produced by your local LM Studio model. Nothing leaves the Mac.")
                    .font(.system(size: 11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(digest.digest)
                    .font(.system(size: 12)).foregroundColor(Theme.text).fixedSize(horizontal: false, vertical: true)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.tileBG))
            }
            Text("Deeper wellness correlation (HRV, sleep) lives in your Claude health copilot, which has the Whoop and Apple Health data. Zest only nudges from what it can see locally.")
                .font(.system(size: 9)).foregroundColor(Theme.ghost).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// Export controls used in Settings > Data.
struct DataExportView: View {
    let export: ExportService
    @State private var lastPath: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHead(label: "EXPORT")
            Text("Write your local battery and energy history to files you can open or share. Saved in Zest's app support folder.").font(.system(size: 10)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Battery health CSV") { lastPath = export.exportBatteryHealthCSV().lastPathComponent }.font(.system(size: 11))
                Button("Energy CSV") { lastPath = export.exportEnergyCSV().lastPathComponent }.font(.system(size: 11))
            }
            HStack {
                Button("Full JSON") { lastPath = export.exportJSON().lastPathComponent }.font(.system(size: 11))
                Button("Weekly report") { lastPath = export.writeWeeklyReport().lastPathComponent }.font(.system(size: 11))
            }
            HStack {
                Button("Reveal in Finder") { export.revealInFinder() }.font(.system(size: 11))
                Spacer()
                if !lastPath.isEmpty { Text("Wrote \(lastPath)").font(.system(size: 10)).foregroundColor(Theme.green) }
            }
        }
    }
}
