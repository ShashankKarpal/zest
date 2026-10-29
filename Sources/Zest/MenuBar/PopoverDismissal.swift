import AppKit

// Closes the dropdown on the first click outside it and on Escape. A .transient popover
// closes on an outside click only while its app is active, and Zest (a menu bar app) was
// not activated when the dropdown opened: a click on the desktop, another app or another
// menu bar icon left it open, and only a click inside it, which activated Zest, armed the
// transient close (owner report 2026-10-29; the same code since v3). Now Zest is activated
// as the dropdown opens, so Escape reaches it, and a global mouse-down monitor closes it,
// which also covers other menu bar icons (opening another app's menu need not deactivate
// Zest). Both monitors exist only while the dropdown is open.
final class PopoverDismissal {
    typealias AddGlobal = (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Any?
    typealias AddLocal = (NSEvent.EventTypeMask, @escaping (NSEvent) -> NSEvent?) -> Any?

    static let outsideClicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    static let escapeKeyCode: UInt16 = 53

    private let addGlobal: AddGlobal
    private let addLocal: AddLocal
    private let removeMonitor: (Any) -> Void
    private let activate: () -> Void
    private let now: () -> Date
    private var monitors: [Any] = []
    private var lastOutsideClose: Date = .distantPast

    init(addGlobal: @escaping AddGlobal = { NSEvent.addGlobalMonitorForEvents(matching: $0, handler: $1) },
         addLocal: @escaping AddLocal = { NSEvent.addLocalMonitorForEvents(matching: $0, handler: $1) },
         removeMonitor: @escaping (Any) -> Void = { NSEvent.removeMonitor($0) },
         activate: @escaping () -> Void = { NSApp.activate(ignoringOtherApps: true) },
         now: @escaping () -> Date = Date.init) {
        self.addGlobal = addGlobal
        self.addLocal = addLocal
        self.removeMonitor = removeMonitor
        self.activate = activate
        self.now = now
    }

    deinit { stop() }

    var isWatching: Bool { !monitors.isEmpty }

    // As the dropdown opens. `close` closes the popover; stop() runs when it has closed.
    func start(close: @escaping () -> Void) {
        stop()
        activate()
        if let m = addGlobal(Self.outsideClicks, { [weak self] _ in
            guard let self else { return }
            self.lastOutsideClose = self.now()
            close()
        }) { monitors.append(m) }
        if let m = addLocal(.keyDown, { event in
            guard event.keyCode == Self.escapeKeyCode else { return event }
            close()
            return nil
        }) { monitors.append(m) }
    }

    func stop() {
        monitors.forEach(removeMonitor)
        monitors.removeAll()
    }

    // If a click on Zest's own icon also reaches the outside-click monitor, the click that
    // closed the dropdown must not open it again.
    func justClosedByOutsideClick(within seconds: TimeInterval = 0.3) -> Bool {
        now().timeIntervalSince(lastOutsideClose) < seconds
    }
}
