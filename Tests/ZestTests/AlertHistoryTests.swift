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

    // Rank 3 of the 2026-10 feature map: on 2026-10-29, 49 of the owner's 50 rows were
    // "Charger connected". Uses only calls the parent has, so it runs against it too.
    func testBackToBackRepeatsShareOneRow() {
        let h = AlertHistory(url: nil)
        func charger(_ hour: Double) {
            h.record(title: "Charger connected", subtitle: "Power adapter plugged in", colorHex: 0x32D74B,
                     suppressed: false, at: Date(timeIntervalSince1970: hour * 3600))
        }
        for hour in 0..<49 { charger(Double(hour)) }
        XCTAssertEqual(h.entries.count, 1, "49 charger alerts in a row are one row")
        XCTAssertEqual(h.entries.first?.ts, 48 * 3600, "the row shows the latest time")

        h.record(title: "Battery dropped to 20%", subtitle: "Consider plugging in soon", colorHex: 0xF59E0B,
                 suppressed: false, at: Date(timeIntervalSince1970: 49 * 3600))
        charger(50)
        XCTAssertEqual(h.entries.map(\.title), ["Charger connected", "Battery dropped to 20%", "Charger connected"],
                       "only back-to-back repeats share a row; the order of events stays")
    }

    func testRepeatRowCountsAndKeepsTheFirstTime() {
        let h = AlertHistory(url: nil)
        for hour in [5.0, 6, 7] {
            h.record(title: "Charger connected", subtitle: "Power adapter plugged in", colorHex: 0x32D74B,
                     suppressed: false, at: Date(timeIntervalSince1970: hour * 3600))
        }
        let row = h.entries.first
        XCTAssertEqual(row?.times, 3)
        XCTAssertEqual(row?.firstDate, Date(timeIntervalSince1970: 5 * 3600))
        XCTAssertEqual(row?.date, Date(timeIntervalSince1970: 7 * 3600))

        // A silenced one, or one with other text, is a different row.
        h.record(title: "Charger connected", subtitle: "Power adapter plugged in", colorHex: 0x32D74B, suppressed: true)
        h.record(title: "Charger connected", subtitle: "Other text", colorHex: 0x32D74B, suppressed: true)
        XCTAssertEqual(h.entries.map(\.times), [1, 1, 3])
    }

    func testFileWrittenBeforeRepeatsFoldsOnLoad() throws {
        // The v3.1.1 format: one row per alert, no repeats or firstTs keys.
        let json = """
        [{"id":"\(UUID().uuidString)","ts":300,"title":"Charger connected","subtitle":"Power adapter plugged in","colorHex":3331915,"suppressed":false},
         {"id":"\(UUID().uuidString)","ts":200,"title":"Charger connected","subtitle":"Power adapter plugged in","colorHex":3331915,"suppressed":false},
         {"id":"\(UUID().uuidString)","ts":100,"title":"Battery dropped to 20%","subtitle":"Consider plugging in soon","colorHex":16096779,"suppressed":false}]
        """
        let list = try JSONDecoder().decode([AlertHistory.Entry].self, from: Data(json.utf8))
        let rows = AlertHistory.trimmed(list)
        XCTAssertEqual(rows.map(\.title), ["Charger connected", "Battery dropped to 20%"])
        XCTAssertEqual(rows.map(\.times), [2, 1])
        XCTAssertEqual(rows.first?.firstTs, 200)
        XCTAssertEqual(rows.first?.id, list.first?.id, "the newest row of a run keeps its id")
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
