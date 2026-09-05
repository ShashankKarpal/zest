import Foundation
import Combine
import AppKit

// Central holder for config and every service. Wires battery/device changes into the
// alert engine and charge limiter. Injected into the SwiftUI environment.
final class AppState: ObservableObject {
    let config: AppConfig
    let battery = BatteryService()
    let batteryHistory = BatteryHistory()
    let devices = DevicesService()
    let energy = EnergySampler()
    let iosDevices = IOSDeviceService()
    let presence = PresenceService()
    let overlay: OverlayManager
    let alertEngine: AlertEngine
    let chargeLimiter: ChargeLimiter
    let digest: DigestService
    let export: ExportService
    let eventLog: EventLog

    // Ported widget panels
    let account1: WidgetPanelRunner
    let account2: WidgetPanelRunner
    let vitals: WidgetPanelRunner
    let claudeCode: WidgetPanelRunner

    private var bag = Set<AnyCancellable>()
    private var autoDismissTimer: Timer?

    init() {
        let cfg = AppConfig.load()
        config = cfg
        overlay = OverlayManager(config: cfg)
        alertEngine = AlertEngine(config: cfg, overlay: overlay)
        chargeLimiter = ChargeLimiter(config: cfg)
        digest = DigestService(battery: battery, history: batteryHistory, energy: energy)
        export = ExportService(history: batteryHistory, energy: energy, battery: battery)
        eventLog = EventLog(directory: cfg.eventLogDir)

        // Personal panels. Inert until the user names a scripts folder in Settings.
        let root = cfg.panelsRoot
        account1 = WidgetPanelRunner(scriptName: "acct1.sh", interval: 30, root: root)
        account2 = WidgetPanelRunner(scriptName: "acct2.sh", interval: 30, root: root)
        vitals = WidgetPanelRunner(scriptName: "vitals.sh", interval: 5, root: root)
        claudeCode = WidgetPanelRunner(scriptName: "cc.sh", interval: 30, root: root)

        chargeLimiter.bind(battery: battery)

        battery.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snap in
                self?.alertEngine.evaluateBattery(snap)
                self?.batteryHistory.record(snap)
                self?.eventLog.observe(snap)
            }
            .store(in: &bag)

        devices.$devices
            .receive(on: RunLoop.main)
            .sink { [weak self] devs in self?.alertEngine.evaluateDevices(devs) }
            .store(in: &bag)

        // Re-publish child changes so views observing AppState update.
        for obj in [battery as any ObservableObject, batteryHistory, devices, energy, iosDevices, presence,
                    chargeLimiter, digest, account1, account2, vitals, claudeCode] as [any ObservableObject] {
            if let pub = (obj.objectWillChange as any Publisher) as? ObservableObjectPublisher {
                pub.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
            }
        }
    }

    var panelRunners: [WidgetPanelRunner] { [account1, account2, vitals, claudeCode] }
    var panelsEnabled: Bool { config.panelsEnabled }

    // True while the Command Center window is on screen; the panel scripts only run
    // while something displays their output (see WidgetPanelRunner.demanded).
    var commandCenterVisible = false { didSet { updatePanelDemand() } }

    func updatePanelDemand() {
        let mode = config.menuBar.claudeMode
        account1.demanded = commandCenterVisible || (mode != .off && !mode.usesAcct2)
        account2.demanded = commandCenterVisible || (mode != .off && mode.usesAcct2)
        vitals.demanded = commandCenterVisible
        claudeCode.demanded = commandCenterVisible
    }

    // Called after the user changes the panels folder in Settings. Also drops the menu
    // bar Claude readout when the panels that feed it are switched off.
    func panelsRootChanged() {
        let root = config.panelsRoot
        panelRunners.forEach { $0.reconfigure(root: root) }
        if !config.panelsEnabled && config.menuBar.claudeMode != .off {
            config.menuBar.claudeMode = .off
        }
        updatePanelDemand()
        objectWillChange.send()
    }

    // Called after the user changes the event log folder in Settings.
    func eventLogDirChanged() {
        eventLog.reconfigure(directory: config.eventLogDir)
        if eventLog.isEnabled { eventLog.lifecycle("zest_start") }
        objectWillChange.send()
    }

    func startPanels() {
        eventLog.lifecycle("zest_start")
        updatePanelDemand()
        panelRunners.forEach { $0.start() }
        // Auto-dismiss the default macOS battery notifications when enabled and trusted.
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.config.autoDismissMacAlerts, MacAlertDismisser.trusted() else { return }
            MacAlertDismisser.dismissBatteryNotifications()
        }
    }

    func shutdown() {
        chargeLimiter.restoreDefaults()
        eventLog.lifecycle("zest_stop")
        eventLog.flush()
        energy.flush()
        config.save()
    }
}
