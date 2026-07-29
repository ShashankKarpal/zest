import AppKit
import SwiftUI
import Combine

// Owns the menu bar status item, the dropdown popover, and the Command Center / Settings
// windows. Redraws the icon whenever the battery snapshot or menu bar style changes.
final class StatusItemController {
    private let state: AppState
    private var statusItem: NSStatusItem!
    private var popover = NSPopover()
    private var commandCenter: NSWindow?
    private var settings: NSWindow?
    private var bag = Set<AnyCancellable>()

    init(state: AppState) {
        self.state = state
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView:
            DropdownView(state: state,
                         openCommandCenter: { [weak self] in self?.showCommandCenter() },
                         openSettings: { [weak self] in self?.showSettings() },
                         toggleLowPowerMode: { LowPowerMode.toggle() })
        )
        redrawIcon()

        state.battery.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.redrawIcon() }
            .store(in: &bag)
        state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.redrawIcon() }
            .store(in: &bag)
    }

    func redrawIcon() {
        guard let button = statusItem.button else { return }
        let img = BatteryIconRenderer.image(snapshot: state.battery.snapshot, style: state.config.menuBar)
        button.image = img

        let mode = state.config.menuBar.claudeMode
        if mode != .off, let text = claudeReadout(mode) {
            button.title = " \(text)"
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    // Reads the session or weekly percent from the relevant account panel's live JSON.
    private func claudeReadout(_ mode: MenuBarClaudeMode) -> String? {
        let runner = mode.usesAcct2 ? state.account2 : state.account1
        let cu = JDict(runner.json).obj("cu")
        guard !cu.isEmpty else { return nil }
        let pct = mode.usesWeekly ? cu.d("weeklyPercentage") : cu.d("sessionPercentage")
        return "\(mode.tag) \(Int(pct.rounded()))%"
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }

    func showCommandCenter() {
        popover.performClose(nil)
        if commandCenter == nil {
            let win = makeWindow(title: "Zest Command Center",
                                 content: CommandCenterView(state: state),
                                 size: NSSize(width: 760, height: 660))
            commandCenter = win
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        commandCenter?.makeKeyAndOrderFront(nil)
    }

    func showSettings() {
        popover.performClose(nil)
        if settings == nil {
            let win = makeWindow(title: "Zest Settings",
                                 content: SettingsView(state: state),
                                 size: NSSize(width: 480, height: 560))
            settings = win
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow<V: View>(title: String, content: V, size: NSSize) -> NSWindow {
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = title
        win.center()
        win.isReleasedWhenClosed = false
        win.titlebarAppearsTransparent = true
        win.contentView = NSHostingView(rootView: content.frame(minWidth: size.width, minHeight: size.height))
        win.appearance = NSAppearance(named: .darkAqua)
        return win
    }
}
