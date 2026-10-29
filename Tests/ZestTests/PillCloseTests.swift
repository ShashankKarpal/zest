import XCTest
import AppKit
import SwiftUI
@testable import Zest

// Audit Z-B10: a pill's close button dismissed NSApp.keyWindow, or the first visible window,
// so with the Command Center open (or two pills on screen) it closed the wrong window.
final class PillCloseTests: XCTestCase {
    private func payload(_ title: String) -> AlertPayload {
        AlertPayload(title: title, subtitle: "", colorHex: 0x32D74B, glow: false, persistent: true,
                     sound: "", position: .topRight, symbol: "powerplug")
    }

    // What the close button runs: the action the pill's view was built with.
    private func pressClose(_ pill: NSWindow) {
        guard let host = pill.contentView as? NSHostingView<PillView> else { return XCTFail("pill content is not a PillView") }
        host.rootView.onClose()
    }

    func testCloseButtonClosesItsOwnPillOnly() {
        _ = NSApplication.shared
        let overlay = OverlayManager(config: AppConfig())
        let size = NSSize(width: 340, height: 92)

        // Stands in for the Command Center: a visible window of the app. Transparent, so a
        // test run draws nothing on screen.
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                             styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        other.alphaValue = 0
        other.orderFrontRegardless()
        defer { other.orderOut(nil) }

        let first = overlay.makePill(payload("Charger connected"), size: size)
        let second = overlay.makePill(payload("Battery dropped to 20%"), size: size)
        for pill in [first, second] { pill.alphaValue = 0; pill.orderFrontRegardless() }
        defer { first.orderOut(nil); second.orderOut(nil) }

        pressClose(second)
        let gone = expectation(for: NSPredicate { _, _ in !second.isVisible }, evaluatedWith: nil)
        wait(for: [gone], timeout: 3)

        XCTAssertFalse(second.isVisible, "the pill whose close button was pressed is gone")
        XCTAssertTrue(first.isVisible, "another pill stays")
        XCTAssertTrue(other.isVisible, "the app's other window stays")
        XCTAssertEqual(overlay.pillWindows, [first])
    }
}
