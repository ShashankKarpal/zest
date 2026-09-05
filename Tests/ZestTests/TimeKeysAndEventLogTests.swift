import XCTest
@testable import Zest

// UTC history keys (audit Z-B9) and the local event feed.
final class TimeKeysAndEventLogTests: XCTestCase {
    // 2026-09-05 04:30:00 UTC == 10:00 IST == 08:30 Dubai.
    private let instant = Date(timeIntervalSince1970: 1_788_582_600)

    func testKeysAreUTCRegardlessOfLocalZone() {
        XCTAssertEqual(TimeKeys.hourKey(instant), "2026-09-05-04")
        XCTAssertEqual(TimeKeys.dayKey(instant), "2026-09-05")
        XCTAssertEqual(TimeKeys.iso8601(instant), "2026-09-05T04:30:00Z")
    }

    func testHourKeyRoundTrip() {
        let key = TimeKeys.hourKey(instant)
        let back = TimeKeys.date(fromHourKey: key)
        XCTAssertEqual(back, Date(timeIntervalSince1970: 1_788_580_800)) // 04:00 UTC bucket start
        XCTAssertNil(TimeKeys.date(fromHourKey: "garbage"))
    }

    func testLegacyISTKeyRekeysToUTCBucketStart() {
        let ist = TimeZone(identifier: "Asia/Kolkata")!
        // 10:00 IST on 2026-09-05 is 04:30 UTC: the bucket start lands in the 04 bucket.
        XCTAssertEqual(TimeKeys.hourKey(rekeying: "2026-09-05-10", from: ist), "2026-09-05-04")
        // 03:00 IST is 21:30 UTC the previous day.
        XCTAssertEqual(TimeKeys.hourKey(rekeying: "2026-09-05-03", from: ist), "2026-09-04-21")
        XCTAssertNil(TimeKeys.hourKey(rekeying: "nope", from: ist))
    }

    func testEnergyHistoryMigrationMergesCollidingBuckets() {
        let dubai = TimeZone(identifier: "Asia/Dubai")! // +04:00: two local hours never collide
        let ist = TimeZone(identifier: "Asia/Kolkata")! // +05:30: 10:00 and 10:30 IST are one UTC hour, but keys are hourly, so test adjacent keys
        let hourly = ["2026-09-05-10": ["A": 10.0], "2026-09-05-11": ["A": 5.0, "B": 1.0]]
        let counts = ["2026-09-05-10": 2, "2026-09-05-11": 3]
        let d = EnergySampler.rekeyToUTC(hourly: hourly, counts: counts, from: dubai)
        XCTAssertEqual(d.hourly["2026-09-05-06"]?["A"], 10.0)
        XCTAssertEqual(d.hourly["2026-09-05-07"]?["B"], 1.0)
        XCTAssertEqual(d.counts["2026-09-05-07"], 3)
        let i = EnergySampler.rekeyToUTC(hourly: hourly, counts: counts, from: ist)
        XCTAssertEqual(i.hourly["2026-09-05-04"]?["A"], 10.0)   // 10:00 IST -> 04:30 -> 04
        XCTAssertEqual(i.hourly["2026-09-05-05"]?["A"], 5.0)    // 11:00 IST -> 05:30 -> 05
        XCTAssertEqual(i.counts.values.reduce(0, +), 5, "no samples lost in migration")
    }

    func testBatteryHistoryNormalizeRederivesDayAndDedupes() {
        let early = BatteryHistory.Sample(day: "wrong", maxCapacity: 95, cycles: 50, tempC: nil, ts: instant.timeIntervalSince1970)
        let later = BatteryHistory.Sample(day: "also-wrong", maxCapacity: 94, cycles: 51, tempC: nil, ts: instant.timeIntervalSince1970 + 3600)
        let other = BatteryHistory.Sample(day: "x", maxCapacity: 96, cycles: 49, tempC: nil, ts: instant.timeIntervalSince1970 - 86400)
        let out = BatteryHistory.normalize([later, early, other])
        XCTAssertEqual(out.map(\.day), ["2026-09-04", "2026-09-05"])
        XCTAssertEqual(out.last?.cycles, 51, "latest sample of the day wins")
    }

    func testTransitionEvents() {
        var a = BatterySnapshot(); a.isACPower = false; a.percent = 40; a.cycleCount = 53
        var b = a; b.isACPower = true; b.adapterWatts = 96
        let plugged = EventLog.events(from: a, to: b)
        XCTAssertEqual(plugged.map(\.event), ["plugged_in"])
        XCTAssertEqual(plugged.first?.fields["adapterWatts"] as? Int, 96)
        var c = b; c.fullyCharged = true; c.percent = 100; c.cycleCount = 54
        let full = EventLog.events(from: b, to: c)
        XCTAssertEqual(Set(full.map(\.event)), ["fully_charged", "charge_cycle"])
        XCTAssertTrue(EventLog.events(from: nil, to: c).isEmpty, "first snapshot is a baseline, not an event")
        XCTAssertTrue(EventLog.events(from: c, to: c).isEmpty)
    }

    func testTemperatureBandsHaveHysteresis() {
        XCTAssertEqual(EventLog.tempLevel(after: 34.9, current: .normal), .normal)
        XCTAssertEqual(EventLog.tempLevel(after: 35.0, current: .normal), .warm)
        XCTAssertEqual(EventLog.tempLevel(after: 34.0, current: .warm), .warm, "stays warm until below 33")
        XCTAssertEqual(EventLog.tempLevel(after: 32.9, current: .warm), .normal)
        XCTAssertEqual(EventLog.tempLevel(after: 40.0, current: .warm), .hot)
        XCTAssertEqual(EventLog.tempLevel(after: 38.5, current: .hot), .hot, "stays hot until below 38")
        XCTAssertEqual(EventLog.tempLevel(after: 37.9, current: .hot), .warm)
        XCTAssertEqual(EventLog.tempLevel(after: 41.0, current: .normal), .hot, "a jump skips straight to hot")
    }

    func testEventLogWritesJSONLinesAndRateLimits() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zest-events-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = EventLog(directory: dir.path)
        XCTAssertTrue(log.isEnabled)
        log.lifecycle("zest_start")
        log.append(EventLog.Event(event: "plugged_in", fields: ["percent": 40]))
        log.append(EventLog.Event(event: "plugged_in", fields: ["percent": 41]))   // same type inside 60 s: dropped
        log.append(EventLog.Event(event: "unplugged", fields: ["percent": 41, "adapterWatts": NSNull()]))
        log.flush()
        let text = try String(contentsOf: dir.appendingPathComponent(EventLog.fileName), encoding: .utf8)
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 3, "start, plugged_in, unplugged; the duplicate plugged_in is rate limited")
        for line in lines {
            let obj = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            XCTAssertEqual(obj?["source"] as? String, "zest")
            XCTAssertTrue((obj?["ts"] as? String)?.hasSuffix("Z") == true, "UTC timestamps")
        }
        let last = try JSONSerialization.jsonObject(with: Data(lines[2].utf8)) as? [String: Any]
        XCTAssertEqual(last?["event"] as? String, "unplugged")
        XCTAssertNil(last?["adapterWatts"], "NSNull fields are omitted, not written as null")
    }

    func testEventLogDisabledWritesNothing() {
        let log = EventLog(directory: nil)
        XCTAssertFalse(log.isEnabled)
        XCTAssertNil(log.fileURL)
        log.append(EventLog.Event(event: "plugged_in"))
        log.flush()
        let empty = EventLog(directory: "")
        XCTAssertFalse(empty.isEnabled)
    }

    func testConfigEventLogDirDefaultsOffAndRoundTrips() throws {
        let off = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        XCTAssertNil(off.eventLogDir); XCTAssertFalse(off.eventLogEnabled)
        let on = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"eventLogDir": "~/tmp/e"}"#.utf8))
        XCTAssertTrue(on.eventLogEnabled)
        let back = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(on))
        XCTAssertEqual(back.eventLogDir, "~/tmp/e")
    }
}
