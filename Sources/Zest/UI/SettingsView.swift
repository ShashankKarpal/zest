import SwiftUI
import AppKit

// Settings: menu bar icon style, battery alert rules, lifecycle alerts, device alerts,
// and general options. Everything writes straight to AppConfig and persists on change.
struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var config: AppConfig
    @State private var tab = 0

    init(state: AppState) {
        self.state = state
        self.config = state.config
    }

    private let sounds = ["Glass", "Ping", "Tink", "Pop", "Sosumi", "Submarine", "Funk", "Hero", "Blow", "Bottle"]

    private func save() { config.save(); state.objectWillChange.send() }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Menu Bar").tag(0); Text("Alerts").tag(1); Text("Lifecycle").tag(2); Text("Devices").tag(3); Text("General").tag(4); Text("Data").tag(5)
            }.pickerStyle(.segmented).padding(12)
            ScrollView { content.padding(16) }
        }
        .frame(width: 480, height: 560)
        .background(Theme.panelBG)
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case 0: menuBarTab
        case 1: alertsTab
        case 2: lifecycleTab
        case 3: devicesTab
        case 5: dataTab
        default: generalTab
        }
    }

    // MARK: Menu bar
    private var menuBarTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHead(label: "MENU BAR ICON")
            toggle("Show percent inside icon", get: { state.config.menuBar.showPercentInsideIcon }, set: { state.config.menuBar.showPercentInsideIcon = $0; save() })
            toggle("Show time remaining instead of %", get: { state.config.menuBar.showTimeRemaining }, set: { state.config.menuBar.showTimeRemaining = $0; save() })
            toggle("Status colors (green/amber/red)", get: { state.config.menuBar.statusColors }, set: { state.config.menuBar.statusColors = $0; save() })
            toggle("Hide the number (minimal)", get: { state.config.menuBar.hideNumber }, set: { state.config.menuBar.hideNumber = $0; save() })
            toggle("Dark glyph (for light menu bars)", get: { state.config.menuBar.darkGlyph }, set: { state.config.menuBar.darkGlyph = $0; save() })

            if config.panelsEnabled {
                Divider1()
                SectionHead(label: "PANEL READOUT IN MENU BAR")
                Text("Optionally show a percent from one of your account panels next to the battery icon.").font(.system(size: 10)).foregroundColor(Theme.faint)
                Picker("Show", selection: Binding(get: { config.menuBar.claudeMode }, set: { config.menuBar.claudeMode = $0; save(); state.updatePanelDemand() })) {
                    ForEach(MenuBarClaudeMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.menu).frame(maxWidth: 260, alignment: .leading)
            }
        }
    }

    // MARK: Widget panels (personal; off unless a folder is chosen)
    private var panelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHead(label: "WIDGET PANELS")
            Text("Point Zest at a folder of panel scripts (acct1.sh, acct2.sh, vitals.sh, cc.sh, made by panels/extract-panels.py) to add four sections to the Command Center. Those scripts are yours and run under your account, exactly as written. Leave this empty and Zest never runs them.")
                .font(.system(size: 10)).foregroundColor(Theme.ghost).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(config.panelsRoot ?? "Not set").font(.system(size: 11, design: .monospaced)).foregroundColor(config.panelsEnabled ? Theme.text : Theme.dim)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose...") { choosePanelsRoot() }
                if config.panelsEnabled {
                    Button("Clear") { config.panelsRoot = nil; save(); state.panelsRootChanged() }
                }
            }
        }
    }

    private func choosePanelsRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use folder"
        panel.message = "Choose the folder that holds your panel scripts."
        if let current = config.panelsRoot { panel.directoryURL = URL(fileURLWithPath: current) }
        if panel.runModal() == .OK, let url = panel.url {
            config.panelsRoot = url.path
            save()
            state.panelsRootChanged()
        }
    }

    // MARK: Alerts
    private var alertsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHead(label: "BATTERY ALERTS")
                Spacer()
                Button("Add") {
                    config.alerts.append(BatteryAlertRule(threshold: 50, direction: .falling))
                    save()
                }.font(.system(size: 11))
            }
            Text("Add as many alerts as you want, at any percentage.").font(.system(size: 10)).foregroundColor(Theme.faint)
            ForEach($config.alerts) { $rule in
                VStack(spacing: 8) {
                    HStack {
                        Toggle("", isOn: $rule.enabled).labelsHidden().onChange(of: rule.enabled) { _ in save() }
                        Stepper("At \(rule.threshold)%", value: $rule.threshold, in: 1...100).onChange(of: rule.threshold) { _ in save() }.font(.system(size: 12))
                        Picker("", selection: $rule.direction) { Text("falling").tag(AlertDirection.falling); Text("rising").tag(AlertDirection.rising) }
                            .frame(width: 100).onChange(of: rule.direction) { _ in save() }
                        Spacer()
                        Button(role: .destructive) { config.alerts.removeAll { $0.id == rule.id }; save() } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundColor(Theme.red)
                    }
                    HStack {
                        Toggle("Glow", isOn: $rule.glow).onChange(of: rule.glow) { _ in save() }.font(.system(size: 11))
                        Toggle("Persistent", isOn: $rule.persistent).onChange(of: rule.persistent) { _ in save() }.font(.system(size: 11))
                        Picker("Sound", selection: $rule.sound) { ForEach(sounds, id: \.self) { Text($0).tag($0) } }.onChange(of: rule.sound) { _ in save() }.frame(width: 130)
                        Picker("Where", selection: $rule.position) { ForEach(PillPosition.allCases, id: \.self) { Text($0.label).tag($0) } }.onChange(of: rule.position) { _ in save() }.frame(width: 130)
                    }
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Theme.tileBG))
            }
        }
    }

    // MARK: Lifecycle
    private var lifecycleTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHead(label: "LIFECYCLE ALERTS")
            ForEach($config.lifecycle) { $rule in
                HStack {
                    Toggle(rule.event.label, isOn: $rule.enabled).onChange(of: rule.enabled) { _ in save() }.font(.system(size: 12))
                    Spacer()
                    Toggle("Glow", isOn: $rule.glow).onChange(of: rule.glow) { _ in save() }.font(.system(size: 11))
                    Picker("Sound", selection: $rule.sound) { ForEach(sounds, id: \.self) { Text($0).tag($0) } }.onChange(of: rule.sound) { _ in save() }.frame(width: 130)
                }.padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Theme.tileBG))
            }
        }
    }

    // MARK: Devices
    private var devicesTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHead(label: "DEVICE ALERTS")
            Text("Detected devices. Toggle to add an alert rule; hide to drop from the leaderboard.").font(.system(size: 10)).foregroundColor(Theme.faint)
            ForEach(state.devices.devices) { dev in
                DeviceSettingRow(state: state, device: dev, sounds: sounds) { save() }
            }
            if state.devices.devices.isEmpty { Text("No devices detected yet.").font(.system(size: 11)).foregroundColor(Theme.faint) }
        }
    }

    // MARK: General
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHead(label: "GENERAL")
            toggle("Launch at login", get: { state.config.launchAtLogin }, set: { state.config.launchAtLogin = $0; LoginItem.set($0); save() })
            VStack(alignment: .leading) {
                Text("Glow intensity").font(.system(size: 12)).foregroundColor(Theme.text)
                Slider(value: Binding(get: { state.config.glowIntensity }, set: { state.config.glowIntensity = $0; save() }), in: 0...1)
            }

            Divider1()
            SectionHead(label: "QUIET HOURS")
            toggle("Silence alerts during a nightly window", get: { config.quietHours.enabled }, set: { config.quietHours.enabled = $0; save() })
            HStack {
                Text("From").font(.system(size: 12)).foregroundColor(Theme.dim)
                Stepper("\(hourLabel(config.quietHours.startHour))", value: Binding(get: { config.quietHours.startHour }, set: { config.quietHours.startHour = $0; save() }), in: 0...23).font(.system(size: 12))
                Text("to").font(.system(size: 12)).foregroundColor(Theme.dim)
                Stepper("\(hourLabel(config.quietHours.endHour))", value: Binding(get: { config.quietHours.endHour }, set: { config.quietHours.endHour = $0; save() }), in: 0...23).font(.system(size: 12))
            }.disabled(!config.quietHours.enabled)
            toggle("Still allow critical low-battery alerts", get: { config.quietHours.allowCritical }, set: { config.quietHours.allowCritical = $0; save() })
            HStack {
                Text("Critical at or below").font(.system(size: 12)).foregroundColor(Theme.dim)
                Stepper("\(config.quietHours.criticalPercent)%", value: Binding(get: { config.quietHours.criticalPercent }, set: { config.quietHours.criticalPercent = $0; save() }), in: 1...30).font(.system(size: 12))
            }.disabled(!config.quietHours.enabled || !config.quietHours.allowCritical)

            Divider1()
            SectionHead(label: "ADVANCED (PERMISSION REQUIRED)")
            toggle("Auto-dismiss macOS battery notifications", get: { state.config.autoDismissMacAlerts }, set: { on in
                state.config.autoDismissMacAlerts = on; save()
                if on && !MacAlertDismisser.trusted() { MacAlertDismisser.requestAccess() }
            })
            Text(MacAlertDismisser.trusted()
                 ? "Accessibility granted. Battery notifications from macOS will be closed automatically. Best-effort; macOS notification internals vary by version."
                 : "Needs Accessibility in System Settings > Privacy & Security. Turning it on opens that pane. Off by default; nothing runs until granted.")
                .font(.system(size: 10)).foregroundColor(Theme.ghost).fixedSize(horizontal: false, vertical: true)
            Divider1()
            panelsSection

            Divider1()
            Text("No license, no accounts, no telemetry. Zest's only network use is the optional battery digest, which talks to your local LM Studio at localhost. Panel scripts you add above do whatever they do; Zest itself sends nothing anywhere.")
                .font(.system(size: 10)).foregroundColor(Theme.ghost).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dataTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            DataExportView(export: state.export)
            Divider1()
            DigestView(digest: state.digest)
        }
    }

    private func toggle(_ label: String, get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: get, set: set)) { Text(label).font(.system(size: 12)).foregroundColor(Theme.text) }.toggleStyle(.switch)
    }

    private func hourLabel(_ h: Int) -> String {
        let period = h < 12 ? "AM" : "PM"
        let twelve = h % 12 == 0 ? 12 : h % 12
        return "\(twelve) \(period)"
    }
}

struct DeviceSettingRow: View {
    @ObservedObject var state: AppState
    let device: AuxDevice
    let sounds: [String]
    var onSave: () -> Void

    var body: some View {
        let ruleIndex = state.config.deviceAlerts.firstIndex { $0.deviceName == device.name }
        let hidden = state.config.hiddenDevices.contains(device.name)
        return HStack {
            Text(device.name).font(.system(size: 12)).foregroundColor(Theme.text).frame(width: 130, alignment: .leading)
            Toggle("Alert", isOn: Binding(get: { ruleIndex != nil }, set: { on in
                if on, ruleIndex == nil { state.config.deviceAlerts.append(DeviceAlertRule(deviceName: device.name)) }
                else if !on, let i = ruleIndex { state.config.deviceAlerts.remove(at: i) }
                onSave()
            })).font(.system(size: 11))
            Toggle("Hide", isOn: Binding(get: { hidden }, set: { on in
                if on { if !hidden { state.config.hiddenDevices.append(device.name) } }
                else { state.config.hiddenDevices.removeAll { $0 == device.name } }
                onSave()
            })).font(.system(size: 11))
            Spacer()
        }.padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Theme.tileBG))
    }
}
