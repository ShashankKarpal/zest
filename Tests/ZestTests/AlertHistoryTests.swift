import XCTest
@testable import Zest

// Alert history: newest first, capped at 50, suppressed alerts recorded too.
final class AlertHistoryTests: XCTestCase {
    func testRecordsNewestFirstAndCaps() {
        let h = AlertHistory(url: nil)
        for i in 0..<60 {
            h.record(title: "Alert \(i)", subtitle: "", colorHex: 0xFFFFFF, suppressed: false,
                     at: Date(timeIntervalSince1970: Double(i)))
        }
        XCTAssertEqual(h.entries.count, AlertHistory.capacity)
        XCTAssertEqual(h.entries.first?.title, "Alert 59")
        XCTAssertEqual(h.entries.last?.title, "Alert 10", "the ten oldest were dropped")
    }

    func testSuppressedFlagAndClear() {
        let h = AlertHistory(url: nil)
        h.record(title: "Low battery", subtitle: "20%", colorHex: 0xF59E0B, suppressed: true)
        XCTAssertTrue(h.entries.first?.suppressed == true)
        h.clear()
        XCTAssertTrue(h.entries.isEmpty)
    }

    func testTrimmedSortsAndCaps() {
        let list = (0..<70).map { AlertHistory.Entry(ts: Double($0), title: "\($0)", subtitle: "", colorHex: 0, suppressed: false) }
        let t = AlertHistory.trimmed(list.shuffled())
        XCTAssertEqual(t.count, 50)
        XCTAssertEqual(t.first?.title, "69")
        XCTAssertEqual(t.last?.title, "20")
    }

    func testPersistsAndReloads() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zest-alerts-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let a = AlertHistory(url: url)
        a.record(title: "Charged above 80%", subtitle: "", colorHex: 0x32D74B, suppressed: false)
        let b = AlertHistory(url: url)
        XCTAssertEqual(b.entries.count, 1)
        XCTAssertEqual(b.entries.first?.title, "Charged above 80%")
    }
}
