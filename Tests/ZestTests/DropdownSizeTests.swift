import XCTest
import SwiftUI
@testable import Zest

// The dropdown popover takes its size from the hosting controller (2026-10-29). It used to
// open at NSPopover's default 320 x 320 whatever the content, cutting it off below the
// power flow.
final class DropdownSizeTests: XCTestCase {
    // Stand-in content with DropdownView's own outer frame: a scroll view of a given height.
    private func preferredSize(contentHeight: CGFloat) -> NSSize {
        _ = NSApplication.shared
        let host = StatusItemController.popoverContent(
            ScrollView { Rectangle().frame(height: contentHeight) }
                .frame(width: DropdownView.width)
                .frame(maxHeight: DropdownView.maxHeight))
        host.view.layoutSubtreeIfNeeded()
        return host.preferredContentSize
    }

    func testShortContentGetsItsOwnHeight() {
        XCTAssertEqual(preferredSize(contentHeight: 500), NSSize(width: DropdownView.width, height: 500))
    }

    func testTallContentStopsAtTheLimitAndScrolls() {
        XCTAssertEqual(preferredSize(contentHeight: 900), NSSize(width: DropdownView.width, height: DropdownView.maxHeight))
    }
}
