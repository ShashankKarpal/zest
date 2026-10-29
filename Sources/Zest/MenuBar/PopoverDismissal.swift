import AppKit
import os

// Closes the dropdown on the first click outside it and on Escape. A .transient popover
// closes on an outside click only while its app is active, and Zest (a menu bar app) was
// not activated when the dropdown opened: a click on the desktop, another app or another
// menu bar icon left it open, and only a click inside it, which activated Zest, armed the
// transient close (owner report 2026-10-29; the same code since v3). Now Zest is activated
// as the dropdown opens, so Escape reaches it, and a global mouse-down monitor closes it,
// which also covers other menu bar icons (opening another app's menu need not deactivate
// Zest). Both monitors exist only while the dropdown is open.
//
// The outside-click monitor ignores a mouse-down inside the dropdown's own window, judged at
// the click's own position. Without that check (f6aaa79), a click on a dropdown button
// closed the dropdown and the button did nothing (owner report 2026-10-29). Each decision
// is a debug-level log line (not kept on disk; `log stream --level debug --predicate
// 'subsystem == "com.shanky.zest"'` shows it live).
final class PopoverDismissal {
    typealias AddGlobal = (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Any?
    typealias AddLocal = (NSEvent.EventTypeMask, @escaping (NSEvent) -> NSEvent?) -> Any?

    static let outsideClicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    static let escapeKeyCode: UInt16 = 53
    private static let log = Logger(subsystem: "com.shanky.zest", category: "dropdown")

    private let addGlobal: AddGlobal
    private let addLocal: AddLocal
    private let removeMonitor: (Any) -> Void
    private let activate: () -> Void
    private let now: () -> Date
    private let locate: (NSEvent) -> NSPoint
    private let isActive: () -> Bool
    private var monitors: [Any] = []
    private var lastOutsideClose: Date = .distantPast
    private var activatedForDropdown = false

    init(addGlobal: @escaping AddGlobal = { NSEvent.addGlobalMonitorForEvents(matching: $0, handler: $1) },
         addLocal: @escaping AddLocal = { NSEvent.addLocalMonitorForEvents(matching: $0, handler: $1) },
         removeMonitor: @escaping (Any) -> Void = { NSEvent.removeMonitor($0) },
         activate: @escaping () -> Void = { NSApp.activate(ignoringOtherApps: true) },
         now: @escaping () -> Date = Date.init,
         locate: @escaping (NSEvent) -> NSPoint = { PopoverDismissal.screenPoint(of: $0) ?? NSEvent.mouseLocation },
         isActive: @escaping () -> Bool = { NSApp.isActive }) {
        self.addGlobal = addGlobal
        self.addLocal = addLocal
        self.removeMonitor = removeMonitor
        self.activate = activate
        self.now = now
        self.locate = locate
        self.isActive = isActive
    }

    deinit { stop() }

    var isWatching: Bool { !monitors.isEmpty }

    // As the dropdown opens. `frame` is the dropdown window's frame in screen coordinates
    // (nil if it has none yet); `isDropdownKey` says whether a key event is aimed at the
    // dropdown, so Escape in another Zest window still reaches that window; `close` closes
    // the popover; stop() runs when it has closed.
    func start(frame: @escaping () -> NSRect?, isDropdownKey: @escaping (NSEvent) -> Bool,
               close: @escaping () -> Void) {
        stop()
        activatedForDropdown = !isActive()
        activate()
        if let m = addGlobal(Self.outsideClicks, { [weak self] event in
            guard let self else { return }
            let point = self.locate(event)
            let box = frame()
            let inside = box?.contains(point) ?? false
            Self.log.debug("click \(inside ? "inside, ignored" : "outside, closing", privacy: .public) at \(String(describing: point), privacy: .public) frame \(box.map { String(describing: $0) } ?? "none", privacy: .public) event window \(event.windowNumber, privacy: .public)")
            guard !inside else { return }
            self.lastOutsideClose = self.now()
            close()
        }) { monitors.append(m) }
        if let m = addLocal(.keyDown, { event in
            guard event.keyCode == Self.escapeKeyCode, isDropdownKey(event) else { return event }
            close()
            return nil
        }) { monitors.append(m) }
    }

    func stop() {
        monitors.forEach(removeMonitor)
        monitors.removeAll()
    }

    // After the dropdown closed: give the focus back only if opening the dropdown is what
    // made Zest active, Zest still is, and no Zest window of its own is showing.
    func shouldHandBackFocus(ownWindowVisible: Bool) -> Bool {
        activatedForDropdown && isActive() && !ownWindowVisible
    }

    // A click's position in screen coordinates (origin bottom left of the main display), from
    // the event itself rather than from where the pointer is when the handler runs. Quartz
    // puts the origin at the top left of the main display.
    static func screenPoint(of event: NSEvent) -> NSPoint? {
        guard let cg = event.cgEvent, let main = NSScreen.screens.first else { return nil }
        return NSPoint(x: cg.location.x, y: main.frame.maxY - cg.location.y)
    }

    // If a click on Zest's own icon also reaches the outside-click monitor, the click that
    // closed the dropdown must not open it again.
    func justClosedByOutsideClick(within seconds: TimeInterval = 0.3) -> Bool {
        now().timeIntervalSince(lastOutsideClose) < seconds
    }
}
