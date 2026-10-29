import XCTest
import AppKit
@testable import Zest

// Owner report 2026-10-29: the dropdown stayed open on a click on the desktop, another app
// or another menu bar icon, and only closed after a click inside it. PopoverDismissal is
// driven here with stand-in monitors, so the test can deliver the events itself.
final class PopoverDismissalTests: XCTestCase {
    private final class Fakes {
        var global: [UInt64: (NSEvent) -> Void] = [:]   // by mask raw value
        var local: [UInt64: (NSEvent) -> NSEvent?] = [:]
        var installed = 0, removed = 0, activations = 0
        var clock = Date(timeIntervalSince1970: 1000)
        var pointer = NSPoint(x: 10, y: 10)            // where the mouse is, screen coordinates
        let dropdown = NSRect(x: 1765, y: 260, width: 386, height: 666)
        lazy var dismissal = PopoverDismissal(
            addGlobal: { [unowned self] mask, h in self.installed += 1; self.global[mask.rawValue] = h; return "g\(self.installed)" },
            addLocal: { [unowned self] mask, h in self.installed += 1; self.local[mask.rawValue] = h; return "l\(self.installed)" },
            removeMonitor: { [weak self] _ in self?.removed += 1 },   // also runs from deinit
            activate: { [unowned self] in self.activations += 1 },
            now: { [unowned self] in self.clock },
            mouseLocation: { [unowned self] in self.pointer })
        func start(_ close: @escaping () -> Void) { dismissal.start(frame: { [unowned self] in self.dropdown }, close: close) }
    }

    private func mouseDown(_ type: NSEvent.EventType = .leftMouseDown) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    private func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                         context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    func testFirstClickOutsideClosesTheDropdown() {
        let f = Fakes()
        var closes = 0
        f.start { closes += 1 }
        XCTAssertEqual(f.activations, 1, "Zest is activated as the dropdown opens, so Escape can reach it")
        let outside = f.global[PopoverDismissal.outsideClicks.rawValue]
        XCTAssertNotNil(outside, "clicks outside Zest are watched while the dropdown is open")
        outside?(mouseDown())
        XCTAssertEqual(closes, 1, "the first click outside closes it")
        outside?(mouseDown(.rightMouseDown))
        XCTAssertEqual(closes, 2)
    }

    // Owner report on f6aaa79: Command Center, Settings, Quit and the Low Power toggle did
    // nothing, because a click on them closed the dropdown on mouse-down. A click inside the
    // dropdown's window must never close it; just outside its edge still does.
    func testClickInsideTheDropdownNeverClosesIt() {
        let f = Fakes()
        var closes = 0
        f.start { closes += 1 }
        let click = f.global[PopoverDismissal.outsideClicks.rawValue]
        for p in [NSPoint(x: 1958, y: 300),           // the bottom row of buttons
                  NSPoint(x: 1766, y: 261),           // just inside the bottom left corner
                  NSPoint(x: 2150, y: 925)] {         // just inside the top right corner
            f.pointer = p
            click?(mouseDown())
            click?(mouseDown(.rightMouseDown))
        }
        XCTAssertEqual(closes, 0, "clicks inside the dropdown leave it open, so its buttons get their click")
        XCTAssertFalse(f.dismissal.justClosedByOutsideClick())

        f.pointer = NSPoint(x: 1764, y: 300)          // one point left of the dropdown
        click?(mouseDown())
        XCTAssertEqual(closes, 1, "a click just outside still closes it")
    }

    func testEscapeClosesAndOtherKeysPassThrough() {
        let f = Fakes()
        var closes = 0
        f.start { closes += 1 }
        let keys = f.local[NSEvent.EventTypeMask.keyDown.rawValue]
        XCTAssertNotNil(keys)
        XCTAssertNotNil(keys?(key(0)), "other keys reach the dropdown")
        XCTAssertEqual(closes, 0)
        XCTAssertNil(keys?(key(PopoverDismissal.escapeKeyCode)), "Escape is used up")
        XCTAssertEqual(closes, 1)
    }

    func testMonitorsAreRemovedOnCloseAndNeverLeak() {
        let f = Fakes()
        f.start {}
        f.start {}            // a second open before a close replaces, never adds
        XCTAssertEqual(f.installed - f.removed, 2)
        f.dismissal.stop()
        XCTAssertEqual(f.installed, f.removed, "every monitor is removed on close")
        XCTAssertFalse(f.dismissal.isWatching)
        f.dismissal.stop()
        XCTAssertEqual(f.installed, f.removed, "a second stop removes nothing twice")
    }

    func testTheClickThatClosedItDoesNotReopenIt() {
        let f = Fakes()
        f.start {}
        f.global[PopoverDismissal.outsideClicks.rawValue]?(mouseDown())
        f.clock.addTimeInterval(0.1)
        XCTAssertTrue(f.dismissal.justClosedByOutsideClick(), "a click on Zest's own icon right after is ignored")
        f.clock.addTimeInterval(0.5)
        XCTAssertFalse(f.dismissal.justClosedByOutsideClick(), "a later click opens it as usual")
    }
}
