import SwiftUI

// The menu bar dropdown (popover). Compact Mac battery status, power flow, health, and a
// device leaderboard, with buttons to the full Command Center and Settings. Scrolls on
// small screens.
struct DropdownView: View {
    @ObservedObject var state: AppState
    var openCommandCenter: () -> Void
    var openSettings: () -> Void
    var toggleLowPowerMode: () -> Void

    var body: some View {
        let snap = state.battery.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Zest").font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                    Spacer()
                    Text(statusLine(snap)).font(.system(size: 11)).foregroundColor(Theme.dim)
                }

                ArcGauge(pct: Double(snap.percent), color: Theme.batteryColor(Double(snap.percent)),
                         big: "\(snap.percent)%", small: arcSub(snap))

                SectionHead(label: "POWER FLOW")
                PowerFlowView(snap: snap)

                let significant = state.energy.window.significant
                if !significant.isEmpty {
                    let sysGrade = EnergyGrade.system(onBattery: !snap.isACPower,
                                                      drainWatts: abs(min(0, snap.batteryWatts)),
                                                      totalMsPerS: state.energy.window.totalLive)
                    Divider1()
                    SectionHead(label: "USING SIGNIFICANT ENERGY", right: sysGrade.label, rightColor: sysGrade.color)
                    ForEach(significant) { app in
                        let grade = EnergyGrade.app(app.value, misbehaving: app.isMisbehaving)
                        HStack(spacing: 8) {
                            Circle().fill(grade.color).frame(width: 6, height: 6)
                            if let icon = AppIcon.image(for: app.name) {
                                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                            } else {
                                Image(systemName: AppIcon.fallbackSymbol(for: app.name))
                                    .font(.system(size: 12)).frame(width: 16, height: 16).foregroundColor(Theme.teal)
                            }
                            Text(app.name).font(.system(size: 12)).foregroundColor(Theme.text).lineLimit(1)
                            Spacer()
                            Text("\(Int(app.value.rounded())) ms/s").font(.system(size: 10)).foregroundColor(grade.color)
                        }
                    }
                }

                Divider1()
                BatteryHealthView(snap: snap)

                Divider1()
                DeviceLeaderboardView(devices: state.devices.devices, hidden: state.config.hiddenDevices)

                Divider1()
                ChargeLimitControls(config: state.config, limiter: state.chargeLimiter) { state.config.save() }

                Divider1()
                HStack(spacing: 8) {
                    Button(action: toggleLowPowerMode) {
                        Label("Low Power: \(state.chargeLimiter.lowPowerOn ? "On" : "Off")", systemImage: "leaf.fill").font(.system(size: 11))
                    }.buttonStyle(.bordered)
                        .help(state.chargeLimiter.helperAvailable ? "Toggle Low Power Mode" : "Needs the zest-smc helper to change (see Command Center > Battery)")
                    Spacer()
                    Button(action: openCommandCenter) { Image(systemName: "square.grid.2x2") }.buttonStyle(.plain).foregroundColor(Theme.dim)
                    Button(action: openSettings) { Image(systemName: "gearshape") }.buttonStyle(.plain).foregroundColor(Theme.dim)
                    Button(action: { NSApp.terminate(nil) }) { Image(systemName: "power") }.buttonStyle(.plain).foregroundColor(Theme.dim)
                }
            }
            .padding(18)
        }
        .frame(width: 360)
        .frame(maxHeight: 640)
        .background(Theme.cardBG)
    }

    private func statusLine(_ s: BatterySnapshot) -> String {
        if s.isCharging, let m = s.timeRemainingMinutes { return "\(m/60)h \(m%60)m to full" }
        if !s.isACPower, let m = s.timeRemainingMinutes { return "\(m/60)h \(m%60)m left" }
        if s.isACPower { return "On adapter" }
        return "On battery"
    }
    private func arcSub(_ s: BatterySnapshot) -> String {
        if s.isCharging { return "⚡ CHARGING" }
        if s.isACPower && s.percent >= 99 { return "⚡ FULL" }
        if s.isACPower { return "⚡ ON ADAPTER" }
        if let m = s.timeRemainingMinutes { return "\(m/60)H \(m%60)M LEFT" }
        return "ON BATTERY"
    }
}
