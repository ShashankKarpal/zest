import SwiftUI

// Full window with a sidebar. Battery-centric sections plus the four ported widget panels
// (which can also pop out as floating cards) and energy insights.
struct CommandCenterView: View {
    @ObservedObject var state: AppState
    @State private var section: Section = .battery

    enum Section: String, CaseIterable, Identifiable {
        case battery = "Battery"
        case energy = "Energy"
        case devices = "Devices"
        case ecosystem = "Ecosystem"
        case iosHealth = "iOS Health"
        case digest = "Digest"
        case account1 = "Account 1"
        case account2 = "Account 2"
        case vitals = "System Vitals"
        case claudeCode = "Claude Code"
        var id: String { rawValue }
        // The four ported widget panels exist only when the user has pointed Zest at a
        // scripts folder (Settings > General > Widget panels). A public build shows six.
        var isPersonalPanel: Bool {
            switch self {
            case .account1, .account2, .vitals, .claudeCode: return true
            default: return false
            }
        }
        var icon: String {
            switch self {
            case .battery: return "battery.100.bolt"
            case .energy: return "bolt.fill"
            case .devices: return "airpods"
            case .ecosystem: return "macbook.and.iphone"
            case .iosHealth: return "iphone"
            case .digest: return "sparkles"
            case .account1: return "1.circle"
            case .account2: return "2.circle"
            case .vitals: return "cpu"
            case .claudeCode: return "chevron.left.forwardslash.chevron.right"
            }
        }
    }

    private var visibleSections: [Section] {
        Section.allCases.filter { state.panelsEnabled || !$0.isPersonalPanel }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 4) {
                Text("ZEST").font(.system(size: 12, weight: .bold)).tracking(2).foregroundColor(Theme.dim).padding(.bottom, 8)
                ForEach(visibleSections) { s in
                    Button(action: { section = s }) {
                        HStack(spacing: 8) {
                            Image(systemName: s.icon).frame(width: 18)
                            Text(s.rawValue).font(.system(size: 12))
                            Spacer()
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .foregroundColor(section == s ? Theme.text : Theme.dim)
                        .background(RoundedRectangle(cornerRadius: 8).fill(section == s ? Color.white.opacity(0.08) : .clear))
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
            .frame(width: 170)
            .padding(12)
            .background(Color.black.opacity(0.25))

            // Content
            ScrollView {
                content.padding(20).frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(minWidth: 600, minHeight: 620)
        .background(Theme.panelBG)
    }

    @ViewBuilder private var content: some View {
        // A personal section that just got switched off falls back to Battery.
        let section = visibleSections.contains(self.section) ? self.section : .battery
        switch section {
        case .battery:
            let snap = state.battery.snapshot
            VStack(alignment: .leading, spacing: 16) {
                ArcGauge(pct: Double(snap.percent), color: Theme.batteryColor(Double(snap.percent)), big: "\(snap.percent)%", small: snap.isCharging ? "CHARGING" : "ON BATTERY").frame(maxWidth: 300)
                SectionHead(label: "POWER FLOW"); PowerFlowView(snap: snap)
                Divider1(); BatteryHealthView(snap: snap, history: state.batteryHistory)
                Divider1(); ChargeLimitControls(config: state.config, limiter: state.chargeLimiter) { state.config.save() }
            }
        case .energy:
            EnergyInsightsView(energy: state.energy, battery: state.battery)
        case .devices:
            DeviceLeaderboardView(devices: state.devices.devices, hidden: state.config.hiddenDevices)
        case .ecosystem:
            EcosystemView(state: state)
        case .iosHealth:
            IOSHealthView(service: state.iosDevices)
        case .digest:
            DigestView(digest: state.digest)
        case .account1:
            Account1Panel(runner: state.account1)
        case .account2:
            Account2Panel(runner: state.account2)
        case .vitals:
            VitalsPanel(runner: state.vitals)
        case .claudeCode:
            ClaudeCodePanel(runner: state.claudeCode)
        }
    }
}
