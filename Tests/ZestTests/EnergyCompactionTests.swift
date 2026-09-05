import XCTest
@testable import Zest

// Hourly energy buckets older than seven days roll up into UTC daily buckets; sums and
// sample counts are additive so window averages are unchanged.
final class EnergyCompactionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_582_600) // 2026-09-05 04:30 UTC

    private func hourKey(daysAgo: Double, hour: Int) -> String {
        let day = TimeKeys.dayKey(now.addingTimeInterval(-daysAgo * 86400))
        return "\(day)-\(String(format: "%02d", hour))"
    }

    func testOldHourlyBucketsFoldIntoTheirUTCDay() {
        let old1 = hourKey(daysAgo: 10, hour: 3), old2 = hourKey(daysAgo: 10, hour: 4)
        let recent = hourKey(daysAgo: 1, hour: 2)
        let hourly = [old1: ["A": 10.0, "B": 2.0], old2: ["A": 5.0], recent: ["A": 1.0]]
        let counts = [old1: 4, old2: 6, recent: 3]
        let r = EnergySampler.compact(hourly: hourly, counts: counts, daily: [:], dailyCounts: [:], now: now)
        XCTAssertEqual(Array(r.hourly.keys), [recent], "only the recent hour stays hourly")
        XCTAssertEqual(r.counts[recent], 3)
        let day = TimeKeys.dayKey(now.addingTimeInterval(-10 * 86400))
        XCTAssertEqual(r.daily[day]?["A"], 15.0)
        XCTAssertEqual(r.daily[day]?["B"], 2.0)
        XCTAssertEqual(r.dailyCounts[day], 10, "sample counts add up so averages stay exact")
    }

    func testCompactionIsIdempotentAndMergesIntoExistingDaily() {
        let old = hourKey(daysAgo: 8, hour: 12)
        let day = TimeKeys.dayKey(now.addingTimeInterval(-8 * 86400))
        let first = EnergySampler.compact(hourly: [old: ["A": 4.0]], counts: [old: 2],
                                          daily: [day: ["A": 6.0]], dailyCounts: [day: 3], now: now)
        XCTAssertEqual(first.daily[day]?["A"], 10.0)
        XCTAssertEqual(first.dailyCounts[day], 5)
        let second = EnergySampler.compact(hourly: first.hourly, counts: first.counts,
                                           daily: first.daily, dailyCounts: first.dailyCounts, now: now)
        XCTAssertEqual(second.daily, first.daily)
        XCTAssertEqual(second.dailyCounts, first.dailyCounts)
    }

    func testDailyBucketsOlderThanThirtyDaysAreDropped() {
        let stale = TimeKeys.dayKey(now.addingTimeInterval(-40 * 86400))
        let kept = TimeKeys.dayKey(now.addingTimeInterval(-20 * 86400))
        let r = EnergySampler.compact(hourly: [:], counts: [:],
                                      daily: [stale: ["A": 1], kept: ["A": 2]], dailyCounts: [stale: 1, kept: 1], now: now)
        XCTAssertNil(r.daily[stale])
        XCTAssertEqual(r.daily[kept]?["A"], 2)
    }

    func testUnparseableHourlyKeysAreDroppedNotCrashed() {
        let r = EnergySampler.compact(hourly: ["garbage": ["A": 1]], counts: ["garbage": 1], daily: [:], dailyCounts: [:], now: now)
        XCTAssertTrue(r.hourly.isEmpty)
        XCTAssertTrue(r.daily.isEmpty)
    }

    func testSevenDayBoundaryKeepsRecentHours() {
        let edgeRecent = TimeKeys.hourKey(now.addingTimeInterval(-EnergySampler.hourlyRetention + 3600))
        let edgeOld = TimeKeys.hourKey(now.addingTimeInterval(-EnergySampler.hourlyRetention - 3600))
        let r = EnergySampler.compact(hourly: [edgeRecent: ["A": 1], edgeOld: ["A": 1]], counts: [edgeRecent: 1, edgeOld: 1],
                                      daily: [:], dailyCounts: [:], now: now)
        XCTAssertNotNil(r.hourly[edgeRecent])
        XCTAssertNil(r.hourly[edgeOld])
        XCTAssertEqual(r.daily.count, 1)
    }
}
