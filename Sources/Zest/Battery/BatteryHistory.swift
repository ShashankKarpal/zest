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
    var projection: (perMonthCycles: Double?, monthsTo80: Int?) {
        let capPoints = samples.compactMap { s -> (Double, Double)? in
            guard let c = s.maxCapacity else { return nil }
            return (s.ts, Double(c))
        }
        guard capPoints.count >= 2, let first = capPoints.first, let last = capPoints.last else { return (nil, nil) }
        let days = max(1, (last.0 - first.0) / 86400)
        // capacity slope in points per day
        let slope = (last.1 - first.1) / days
        var monthsTo80: Int? = nil
        if slope < -0.0001 {
            let remaining = last.1 - 80
            let daysTo80 = remaining / (-slope)
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

    private static func dayKey(_ d: Date = Date()) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }
    private func load() {
        guard let data = try? Data(contentsOf: url), let arr = try? JSONDecoder().decode([Sample].self, from: data) else { return }
        samples = arr.sorted { $0.day < $1.day }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(samples) { try? data.write(to: url) }
    }
}
