import SwiftUI

// Live animated power flow: adapter -> battery -> Mac, with real wattage read from the
// AppleSmartBattery AdapterDetails and Voltage x InstantAmperage. Dots animate along the
// path whose direction follows charge vs discharge.
struct PowerFlowView: View {
    let snap: BatterySnapshot
    @State private var phase: CGFloat = 0

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
        .onAppear { withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 } }
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
                    ForEach(0..<3, id: \.self) { i in
                        Circle().fill(color)
                            .frame(width: 4, height: 4)
                            .offset(x: dotX(w: w, i: i, reverse: reverse))
                    }
                }
            }.frame(maxHeight: .infinity, alignment: .center)
        }.frame(height: 24)
    }

    private func dotX(w: CGFloat, i: Int, reverse: Bool) -> CGFloat {
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
