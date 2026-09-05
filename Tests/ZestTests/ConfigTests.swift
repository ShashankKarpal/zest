import XCTest
@testable import Zest

// AppConfig decoding must be tolerant (an old config keeps working) and the panel gate
// must default to OFF. These tests decode JSON directly and never touch the real
// ~/Library/Application Support/Zest folder.
final class ConfigTests: XCTestCase {
    private func decode(_ json: String) throws -> AppConfig {
        try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    }

    func testEmptyObjectDecodesToDefaultsWithPanelsOff() throws {
        let cfg = try decode("{}")
        XCTAssertNil(cfg.panelsRoot)
        XCTAssertFalse(cfg.panelsEnabled)
        XCTAssertEqual(cfg.alerts.count, AppConfig.defaultAlerts().count)
        XCTAssertEqual(cfg.menuBar.claudeMode, .off)
        XCTAssertFalse(cfg.autoDismissMacAlerts)
    }

    func testEmptyPanelsRootMeansOff() throws {
        let cfg = try decode(#"{"panelsRoot": ""}"#)
        XCTAssertNil(cfg.panelsRoot)
        XCTAssertFalse(cfg.panelsEnabled)
    }

    func testPanelsRootEnablesPanels() throws {
        let cfg = try decode(#"{"panelsRoot": "/tmp/my-panels"}"#)
        XCTAssertEqual(cfg.panelsRoot, "/tmp/my-panels")
        XCTAssertTrue(cfg.panelsEnabled)
    }

    func testPanelsRootRoundTripsThroughEncoder() throws {
        let cfg = AppConfig()
        cfg.panelsRoot = "/tmp/round-trip"
        let data = try JSONEncoder().encode(cfg)
        let back = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(back.panelsRoot, "/tmp/round-trip")
    }

    func testNilPanelsRootIsOmittedFromEncodedJSON() throws {
        let data = try JSONEncoder().encode(AppConfig())
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(obj)
        XCTAssertNil(obj?["panelsRoot"], "a fresh config must not carry a panelsRoot key")
    }

    func testMalformedSectionFallsBackToDefaultsNotFailure() throws {
        // menuBar is garbage, alerts is the wrong type: both must fall back, not throw.
        let cfg = try decode(#"{"menuBar": 42, "alerts": "nope", "glowIntensity": 0.3}"#)
        XCTAssertEqual(cfg.menuBar.claudeMode, .off)
        XCTAssertEqual(cfg.alerts.count, AppConfig.defaultAlerts().count)
        XCTAssertEqual(cfg.glowIntensity, 0.3, accuracy: 0.0001)
    }

    func testMenuBarStyleTolerantDecode() throws {
        let style = try JSONDecoder().decode(MenuBarStyle.self, from: Data(#"{"hideNumber": true}"#.utf8))
        XCTAssertTrue(style.hideNumber)
        XCTAssertTrue(style.showPercentInsideIcon)
        XCTAssertEqual(style.claudeMode, .off)
    }

    func testQuietHoursOvernightWrap() {
        var q = QuietHours(); q.enabled = true; q.startHour = 22; q.endHour = 8
        XCTAssertTrue(q.contains(hour: 23))
        XCTAssertTrue(q.contains(hour: 3))
        XCTAssertFalse(q.contains(hour: 8))
        XCTAssertFalse(q.contains(hour: 12))
        q.enabled = false
        XCTAssertFalse(q.contains(hour: 23))
    }
}
