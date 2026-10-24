import XCTest
@testable import Zest

// The helper probe tells a current helper (v3.1 grant: exact argument vectors) from one
// installed before v3.1 (grant: the helper with any arguments), which must be re-installed.
final class HelperProbeTests: XCTestCase {
    func testCurrentHelperAsRoot() {
        XCTAssertEqual(ZestHelper.probeResult("ok root helper 2\n"), .current)
    }

    func testNewerHelperCountsAsCurrent() {
        XCTAssertEqual(ZestHelper.probeResult("ok root helper 3\n"), .current)
    }

    func testPreV31HelperIsOutdated() {
        // The v3.0 helper's whole answer.
        XCTAssertEqual(ZestHelper.probeResult("ok root\n"), .outdated)
        XCTAssertEqual(ZestHelper.probeResult("ok"), .outdated)
    }

    func testOlderInterfaceOrGarbageNumberIsOutdated() {
        XCTAssertEqual(ZestHelper.probeResult("ok root helper 1"), .outdated)
        XCTAssertEqual(ZestHelper.probeResult("ok root helper"), .outdated)
        XCTAssertEqual(ZestHelper.probeResult("ok root helper two"), .outdated)
    }

    func testSudoWarningBeforeTheAnswerIsIgnored() {
        XCTAssertEqual(ZestHelper.probeResult("sudo: unable to resolve host x\nok root helper 2\n"), .current)
        XCTAssertEqual(ZestHelper.probeResult("sudo: unable to resolve host x\nok root\n"), .outdated)
    }

    func testNoGrantOrNoAnswerIsUnavailable() {
        XCTAssertEqual(ZestHelper.probeResult("sudo: a password is required\n"), .unavailable)
        XCTAssertEqual(ZestHelper.probeResult(""), .unavailable)
        XCTAssertEqual(ZestHelper.probeResult("error unknown-command probe"), .unavailable)
    }
}
