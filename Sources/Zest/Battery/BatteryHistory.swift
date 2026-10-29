import Foundation
import Combine

// Persists one battery-health sample per day (max capacity, cycle count, temperature) and
// exposes the series for a trendline. No permissions needed. Stored as JSON in
// ~/Library/Application Support/Zest/health-history.json.
final class BatteryHistory: ObservableObject {
    struct Sample: Codable, Identifiable {
        var id: String { day }
        var day: String        // yyyy-MM-dd
        var maxCapacity: Int?
        var cycles: Int?
        var tempC: Double?
        var ts: Double
    }

    @Published private(set) var samples: [Sample] = []

    private let url = AppConfig.dir.appendingPathComponent("health-history.json")

    init() { load() }

    // Called on battery refresh; records at most one sample per calendar day.
    func record(_ snap: BatterySnapshot) {
        guard snap.maxCapacityPercent != nil || snap.cycleCount != nil else { return }
        let day = Self.dayKey()
        let sample = Sample(day: day, maxCapacity: snap.maxCapacityPercent, cycles: snap.cycleCount, tempC: snap.temperatureC, ts: Date().timeIntervalSince1970)
        if let idx = samples.firstIndex(where: { $0.day == day }) {
            samples[idx] = sample
        } else {
            samples.append(sample)
            samples.sort { $0.day < $1.day }
        }
        // keep two years of daily points
        if samples.count > 730 { samples.removeFirst(samples.count - 730) }
        save()
    }

    // Estimated cycles/month and a simple linear projection of when capacity hits 80%.
    var projection: (perMonthCycles: Double?, monthsTo80: Int?) { Self.projection(of: samples) }

    // Pure function over a sample series so it can be tested without touching disk.
    static func projection(of samples: [Sample]) -> (perMonthCycles: Double?, monthsTo80: Int?) {
        let capPoints = samples.compactMap { s -> (ts: Double, value: Double)? in
            guard let c = s.maxCapacity else { return nil }
            return (s.ts, Double(c))
        }
        // No capacity trend yet still leaves the cycle rate, which has its own data.
        var monthsTo80: Int? = nil
        if let fit = capacityTrend(capPoints), fit.slope < -0.0001 {
            let remaining = fit.now - 80
            let daysTo80 = remaining / (-fit.slope)
            if daysTo80 > 0 { monthsTo80 = Int((daysTo80 / 30).rounded()) }
        }
        // cycles per month
        var perMonth: Double? = nil
        let cyc = samples.compactMap { s -> (Double, Double)? in s.cycles.map { (s.ts, Double($0)) } }
        if let cf = cyc.first, let cl = cyc.last, cl.0 > cf.0 {
            let months = (cl.0 - cf.0) / 86400 / 30
            if months > 0.1 { perMonth = (cl.1 - cf.1) / months }
        }
        return (perMonth, monthsTo80)
    }

    // Least-squares line through every (time, capacity) point: the slope in points per day
    // and the line's value at the newest point. The projection used to draw its line through
    // the first and last samples only, so one odd reading at either end set the whole
    // projection (audit Z-B11). Nil with fewer than two points or under a day between the
    // oldest and newest: the old line clamped that gap to one day, and two daily samples
    // can sit minutes apart (23:58 and 00:02 UTC), which would make the line near vertical.
    static func capacityTrend(_ points: [(ts: Double, value: Double)]) -> (slope: Double, now: Double)? {
        guard points.count >= 2, let t0 = points.map(\.ts).min(), let tNew = points.map(\.ts).max() else { return nil }
        let xs = points.map { ($0.ts - t0) / 86400 }
        let n = Double(points.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = points.map(\.value).reduce(0, +) / n
        var sxx = 0.0, sxy = 0.0
        for (x, p) in zip(xs, points) {
            sxx += (x - meanX) * (x - meanX)
            sxy += (x - meanX) * (p.value - meanY)
        }
        guard sxx > 0, tNew - t0 >= 86400 else { return nil }
        let slope = sxy / sxx
        return (slope, meanY + slope * ((tNew - t0) / 86400 - meanX))
    }

    // UTC day keys since 2026-09-05 (audit Z-B9); the old local-zone key would have moved
    // every sample by a day at the 2026-09-15 timezone change.
    private static func dayKey(_ d: Date = Date()) -> String { TimeKeys.dayKey(d) }

    // Every sample carries its instant (`ts`), so the day key is re-derived in UTC on
    // load and same-day duplicates collapse to the latest. Pure for testing.
    static func normalize(_ arr: [Sample]) -> [Sample] {
        var byDay: [String: Sample] = [:]
        for var s in arr {
            s.day = TimeKeys.dayKey(Date(timeIntervalSince1970: s.ts))
            if let existing = byDay[s.day], existing.ts >= s.ts { continue }
            byDay[s.day] = s
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url), let arr = try? JSONDecoder().decode([Sample].self, from: data) else { return }
        let normalized = Self.normalize(arr)
        samples = normalized
        if normalized.map(\.day) != arr.map(\.day) { save() }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(samples) { try? data.write(to: url, options: .atomic) }
    }
}
