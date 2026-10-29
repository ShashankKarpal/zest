import AppKit

// Closes the dropdown on the first click outside it and on Escape. A .transient popover
// closes on an outside click only while its app is active, and Zest (a menu bar app) was
// not activated when the dropdown opened: a click on the desktop, another app or another
// menu bar icon left it open, and only a click inside it, which activated Zest, armed the
// transient close (owner report 2026-10-29; the same code since v3). Now Zest is activated
// as the dropdown opens, so Escape reaches it, and a global mouse-down monitor closes it,
// which also covers other menu bar icons (opening another app's menu need not deactivate
// Zest). Both monitors exist only while the dropdown is open.
//
// The outside-click monitor ignores a mouse-down inside the dropdown's own window. Without
// that check (f6aaa79), a click on a dropdown button closed the dropdown on mouse-down, so
// the button's action never ran (owner report 2026-10-29). Each decision is logged, one
// line per click while the dropdown is open, with the event's window number.
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
    private let mouseLocation: () -> NSPoint
    private var monitors: [Any] = []
    private var lastOutsideClose: Date = .distantPast

    init(addGlobal: @escaping AddGlobal = { NSEvent.addGlobalMonitorForEvents(matching: $0, handler: $1) },
         addLocal: @escaping AddLocal = { NSEvent.addLocalMonitorForEvents(matching: $0, handler: $1) },
         removeMonitor: @escaping (Any) -> Void = { NSEvent.removeMonitor($0) },
         activate: @escaping () -> Void = { NSApp.activate(ignoringOtherApps: true) },
         now: @escaping () -> Date = Date.init,
         mouseLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation }) {
        self.addGlobal = addGlobal
        self.addLocal = addLocal
        self.removeMonitor = removeMonitor
        self.activate = activate
        self.now = now
        self.mouseLocation = mouseLocation
    }

    deinit { stop() }

    var isWatching: Bool { !monitors.isEmpty }

    // As the dropdown opens. `frame` is the dropdown window's frame in screen coordinates
    // (nil if it has none yet); `close` closes the popover; stop() runs when it has closed.
    func start(frame: @escaping () -> NSRect?, close: @escaping () -> Void) {
        stop()
        activate()
        if let m = addGlobal(Self.outsideClicks, { [weak self] event in
            guard let self else { return }
            let point = self.mouseLocation()
            let box = frame()
            let inside = box?.contains(point) ?? false
            NSLog("Zest: dropdown click monitor: \(inside ? "inside, ignored" : "outside, closing") at \(point) in \(box.map { "\($0)" } ?? "no frame") (event window \(event.windowNumber))")
            guard !inside else { return }
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
