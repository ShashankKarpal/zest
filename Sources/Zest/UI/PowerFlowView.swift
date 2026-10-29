import SwiftUI

// Live animated power flow: adapter -> battery -> Mac, with real wattage read from the
// AppleSmartBattery AdapterDetails and Voltage x InstantAmperage. Dots move along the
// path whose direction follows charge vs discharge.
//
// The dots take their place from the clock (TimelineView), not from an animation. The old
// `withAnimation(.repeatForever) { phase = 1 }` in onAppear never moved them (phase 0 and
// phase 1 put every dot in the same place), but its endless transaction caught the
// dropdown's first layout: the whole card collapsed and regrew every 1.2 s while open
// (2026-10-29). Nothing here animates layout now.
struct PowerFlowView: View {
    let snap: BatterySnapshot
    static let dotCycle: TimeInterval = 1.2   // seconds for a dot to cross one link

    var body: some View {
        let adapterW = Double(snap.adapterWatts ?? 0)
        let battW = snap.batteryWatts
        let systemW = snap.systemWatts
        let charging = battW > 0.5

        return VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 0) {
                node(icon: "powerplug.fill", label: snap.isACPower ? "\(Int(adapterW))W" : "No adapter", sub: "Adapter", color: snap.isACPower ? Theme.green : Theme.faint)
                flow(active: snap.isACPower, color: Theme.green, reverse: false)
                node(icon: "battery.100", label: "\(snap.percent)%", sub: battW >= 0 ? "Battery +\(String(format: "%.1f", abs(battW)))W" : "Battery -\(String(format: "%.1f", abs(battW)))W", color: Theme.batteryColor(Double(snap.percent)))
                flow(active: systemW > 0.1, color: Theme.blue, reverse: !charging && !snap.isACPower ? true : false)
                node(icon: "laptopcomputer", label: "\(String(format: "%.1f", systemW))W", sub: "System", color: Theme.blue)
            }
            if snap.adapterUnderpowered {
                Text("Adapter may be underpowered for the current load")
                    .font(.system(size: 10)).foregroundColor(Theme.orange)
            }
            HStack(spacing: 16) {
                metric("Voltage", snap.voltageV.map { String(format: "%.2f V", $0) } ?? "--")
                metric("Amperage", snap.amperageMA.map { "\($0) mA" } ?? "--")
                metric("Adapter", snap.adapterName ?? (snap.isACPower ? "USB-C" : "None"))
            }
        }
    }

    private func node(icon: String, label: String, sub: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 20)).foregroundColor(color)
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
            Text(sub).font(.system(size: 9)).foregroundColor(Theme.faint)
        }.frame(width: 76)
    }

    private func flow(active: Bool, color: Color, reverse: Bool) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 2)
                if active {
                    // 30 frames a second is smooth for 4 pt dots and half the work of 60.
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                        let phase = Self.phase(at: context.date)
                        ZStack {
                            ForEach(0..<3, id: \.self) { i in
                                Circle().fill(color)
                                    .frame(width: 4, height: 4)
                                    .offset(x: Self.dotX(phase: phase, width: w, index: i, reverse: reverse))
                            }
                        }
                    }
                }
            }.frame(maxHeight: .infinity, alignment: .center)
        }.frame(height: 24)
    }

    // Where in the cycle the dots are at `date`, 0 up to (not including) 1.
    static func phase(at date: Date) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: dotCycle)
        return CGFloat((t < 0 ? t + dotCycle : t) / dotCycle)
    }

    // Horizontal offset of dot `index` (three dots, a third of a cycle apart) from the centre
    // of a link `width` wide.
    static func dotX(phase: CGFloat, width w: CGFloat, index i: Int, reverse: Bool) -> CGFloat {
        let base = (phase + CGFloat(i) / 3).truncatingRemainder(dividingBy: 1)
        let p = reverse ? (1 - base) : base
        return -w/2 + p * w
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.text)
            Text(label).font(.system(size: 9)).foregroundColor(Theme.faint)
        }.frame(maxWidth: .infinity)
    }
}
