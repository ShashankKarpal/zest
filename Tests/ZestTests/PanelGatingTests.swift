import XCTest
@testable import Zest

// The personal panels must be inert without a configured folder: no script path, no
// spawn, and the four personal Command Center sections hidden.
final class PanelGatingTests: XCTestCase {
    func testRunnerWithoutRootIsInert() {
        let r = WidgetPanelRunner(scriptName: "acct1.sh", interval: 30, root: nil)
        XCTAssertFalse(r.isConfigured)
        XCTAssertNil(r.scriptPath)
        r.start()      // must be a no-op, not a crash and not a bash spawn
        r.refresh()
        XCTAssertTrue(r.json.isEmpty)
        XCTAssertNil(r.lastUpdated)
        r.stop()
    }

    func testRunnerWithEmptyRootIsInert() {
        let r = WidgetPanelRunner(scriptName: "vitals.sh", interval: 5, root: "")
        XCTAssertFalse(r.isConfigured)
    }

    func testRunnerResolvesScriptUnderRootAndExpandsTilde() {
        let r = WidgetPanelRunner(scriptName: "cc.sh", interval: 30, root: "~/some/panels")
        XCTAssertTrue(r.isConfigured)
        XCTAssertEqual(r.scriptPath, NSString(string: "~/some/panels/cc.sh").expandingTildeInPath)
        XCTAssertFalse(r.scriptPath!.contains("~"))
    }

    func testReconfigureToNilClearsPathAndData() {
        let r = WidgetPanelRunner(scriptName: "acct2.sh", interval: 30, root: "/tmp/panels")
        XCTAssertTrue(r.isConfigured)
        r.reconfigure(root: nil)
        XCTAssertFalse(r.isConfigured)
        XCTAssertNil(r.scriptPath)
        XCTAssertTrue(r.json.isEmpty)
    }

    func testMissingScriptFileNeverSpawns() {
        // A configured root whose script does not exist must report, not run bash.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zest-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = WidgetPanelRunner(scriptName: "acct1.sh", interval: 30, root: dir.path)
        r.refresh()
        let exp = expectation(description: "main queue drained")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertTrue(r.raw.hasPrefix("Panel script not found:"), "got: \(r.raw)")
        XCTAssertTrue(r.json.isEmpty)
    }

    func testExactlyFourSectionsArePersonal() {
        let all = CommandCenterView.Section.allCases
        let personal = all.filter { $0.isPersonalPanel }
        XCTAssertEqual(personal.count, 4)
        XCTAssertEqual(all.count - personal.count, 7, "public build shows seven sections")
        XCTAssertEqual(Set(personal.map(\.rawValue)), ["Account 1", "Account 2", "System Vitals", "Claude Code"])
    }
}
