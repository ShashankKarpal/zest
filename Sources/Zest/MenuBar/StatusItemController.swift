import AppKit
import SwiftUI
import Combine

// Owns the menu bar status item, the dropdown popover, and the Command Center / Settings
// windows. Redraws the icon when what it shows changes (MenuBarIconUpdater).
//
// The dropdown's SwiftUI tree exists only while the popover is open. It holds
// PowerFlowView, whose animation repeats forever; with a hosting controller kept for the
// app's lifetime it never saw onDisappear, so after the first click the closed popover was
// laid out and rendered on every display frame: about 30 percent CPU for Zest and a busy
// WindowServer until Zest quit (2026-10-29). A closed Command Center window does not do
// this (measured the same day), so it is kept between opens as before.
final class StatusItemController {
    private let state: AppState
    private var statusItem: NSStatusItem!
    private var popover = NSPopover()
    private var iconUpdater: MenuBarIconUpdater!
    private let dismissal = PopoverDismissal()
    private var popoverCloseObserver: NSObjectProtocol?
    private var screensObserver: NSObjectProtocol?
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
        popoverCloseObserver = NotificationCenter.default.addObserver(forName: NSPopover.didCloseNotification, object: popover, queue: .main) { [weak self] _ in
            // Not if a quick reopen already started watching again.
            if self?.popover.isShown == false { self?.dismissal.stop() }
            // After the close finishes; a quick reopen keeps its content.
            DispatchQueue.main.async {
                guard let self, !self.popover.isShown else { return }
                self.popover.contentViewController = nil
                // The dropdown activated Zest; with no window of its own left open, hand the
                // focus back to the app that had it.
                if self.dismissal.shouldHandBackFocus(
                    ownWindowVisible: NSApp.windows.contains(where: { $0.isVisible && $0.styleMask.contains(.titled) })) {
                    NSApp.deactivate()
                }
            }
        }

        iconUpdater = MenuBarIconUpdater(
            current: { [unowned self] in self.currentIcon() },
            setImage: { [unowned self] glyph in self.statusItem.button?.image = BatteryIconRenderer.image(glyph) },
            setTitle: { [unowned self] text in
                guard let button = self.statusItem.button else { return }
                if let text {
                    button.title = " \(text)"
                    button.imagePosition = .imageLeading
                } else {
                    button.title = ""
                    button.imagePosition = .imageOnly
                }
            },
            canDraw: { [unowned self] in self.statusItem.button != nil })
        iconUpdater.updateNow()
        screensObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.iconUpdater.invalidate()
        }

        state.battery.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.iconUpdater.setNeedsUpdate() }
            .store(in: &bag)
        state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.iconUpdater.setNeedsUpdate() }
            .store(in: &bag)
    }

    deinit { [popoverCloseObserver, screensObserver].compactMap { $0 }.forEach { NotificationCenter.default.removeObserver($0) } }

    private func currentIcon() -> MenuBarIcon {
        let style = state.config.menuBar
        let title = style.claudeMode == .off ? nil : claudeReadout(style.claudeMode)
        return MenuBarIcon(snapshot: state.battery.snapshot, style: style, title: title)
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
        else {
            guard !dismissal.justClosedByOutsideClick() else { return }
            if popover.contentViewController == nil {
                popover.contentViewController = Self.popoverContent(
                    DropdownView(state: state,
                                 openCommandCenter: { [weak self] in self?.showCommandCenter() },
                                 openSettings: { [weak self] in self?.showSettings() },
                                 toggleLowPowerMode: { [weak self] in self?.state.chargeLimiter.toggleLowPower() })
                )
            }
            dismissal.start(frame: { [weak self] in self?.popover.contentViewController?.view.window?.frame },
                            close: { [weak self] in self?.popover.performClose(nil) })
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // NSPopover sizes itself from the controller's preferredContentSize, which a hosting
    // controller leaves at zero unless asked. The popover then fell back to 320 x 320 and
    // cut the dropdown off below the power flow. Now it fits the content up to
    // DropdownView.maxHeight and scrolls beyond that.
    static func popoverContent<V: View>(_ view: V) -> NSHostingController<V> {
        let host = NSHostingController(rootView: view)
        host.sizingOptions = .preferredContentSize
        return host
    }

    func showCommandCenter() {
        popover.performClose(nil)
        if commandCenter == nil {
            let win = makeWindow(title: "Zest Command Center",
                                 content: CommandCenterView(state: state),
                                 size: NSSize(width: 760, height: 660))
            commandCenter = win
            // Panel scripts run only while this window is open.
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: win, queue: .main) { [weak self] _ in
                self?.state.commandCenterVisible = false
            }
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        commandCenter?.makeKeyAndOrderFront(nil)
        state.commandCenterVisible = true
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
