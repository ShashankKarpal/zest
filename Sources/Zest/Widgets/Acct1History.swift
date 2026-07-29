import Foundation

// Mirrors the Account 1 widget's 7-day history aggregation over TokenEater
// history.entries[].buckets[]. Same COCOA epoch, same model/project/session math, so the
// derived stats match the original card.
enum Acct1History {
    struct Day { var key: String; var label: String; var full: String; var models: [String: Double] }
    struct Result {
        var days: [Day] = []
        var maxDaily: Double = 1
        var weekSum: Double = 0
        var modelTotals: [String: Double] = [:]
        var cacheTotal: Double = 0
        var cacheHit: Int = 0
        var activeTotal: Double = 0
        var sessions: Int = 0
        var avgPerSession: Double = 0
        var heaviest: String = "n/a"
        var heaviestTokens: Double = 0
        var topModel: String = "n/a"
        var topModelPct: Int = 0
        var topProject: String = "n/a"
    }

    static func aggregate(history: JDict, weeklyReset: Date) -> Result {
        var r = Result()
        let now = Date()
        let cal = Calendar.current

        // Build the 7 calendar-day buckets.
        var days: [Day] = []
        var dayIndex: [String: Int] = [:]
        for i in stride(from: 6, through: 0, by: -1) {
            let d = cal.date(byAdding: .day, value: -i, to: now)!
            let comps = cal.dateComponents([.year, .month, .day], from: d)
            let key = "\(comps.year!)-\(comps.month!-1)-\(comps.day!)"   // matches JS getMonth() 0-based
            let lf = DateFormatter(); lf.dateFormat = "EEE"
            let ff = DateFormatter(); ff.dateFormat = "MMM d"
            days.append(Day(key: key, label: String(lf.string(from: d).prefix(2)), full: ff.string(from: d), models: [:]))
            dayIndex[key] = days.count - 1
        }

        let windowStart = now.addingTimeInterval(-7 * 86400).timeIntervalSince1970 * 1000
        var cacheRead = 0.0, cacheCreate = 0.0, activeTotal = 0.0
        var modelTotals: [String: Double] = [:]
        var projectTotals: [String: Double] = [:]
        var sessionSet = Set<String>()

        let entryList: [Any] = (history["entries"] as? [String: Any]).map { Array($0.values) } ?? []

        for entryAny in entryList {
            guard let entry = entryAny as? [String: Any] else { continue }
            let buckets = entry["buckets"] as? [[String: Any]] ?? []
            var contributed = false
            for b in buckets {
                let dateSecs = (b["date"] as? Double) ?? Double((b["date"] as? Int) ?? 0)
                let bMs = (dateSecs + TimeFmt.cocoa) * 1000
                if bMs < windowStart { continue }
                contributed = true
                cacheRead += num(b["cacheReadTokens"])
                cacheCreate += num(b["cacheCreateTokens"])
                activeTotal += num(b["inputTokens"]) + num(b["outputTokens"])
                let d = Date(timeIntervalSince1970: bMs / 1000)
                let comps = cal.dateComponents([.year, .month, .day], from: d)
                let key = "\(comps.year!)-\(comps.month!-1)-\(comps.day!)"
                if let tbm = b["tokensByModel"] as? [Any] {
                    var i = 0
                    while i < tbm.count - 1 {
                        let name = ModelMeta.norm((tbm[i] as? String) ?? "other")
                        let val = num(tbm[i+1])
                        modelTotals[name, default: 0] += val
                        if let idx = dayIndex[key] { days[idx].models[name, default: 0] += val }
                        i += 2
                    }
                }
                if let proj = b["tokensByProject"] as? [String: Any] {
                    for (p, v) in proj { projectTotals[p, default: 0] += num(v) }
                }
            }
            if contributed, let ids = entry["sessionIds"] as? [Any] {
                for id in ids { if let s = id as? String { sessionSet.insert(s) } }
            }
        }

        let dailyTotals = days.map { $0.models.values.reduce(0, +) }
        r.days = days
        r.maxDaily = max(dailyTotals.max() ?? 1, 1)
        r.weekSum = dailyTotals.reduce(0, +)
        r.modelTotals = modelTotals
        r.activeTotal = activeTotal
        r.cacheTotal = cacheRead + cacheCreate
        r.cacheHit = r.cacheTotal > 0 ? Int((cacheRead / r.cacheTotal * 100).rounded()) : 0
        r.sessions = sessionSet.count
        r.avgPerSession = r.sessions > 0 ? activeTotal / Double(r.sessions) : 0

        if let maxIdx = dailyTotals.indices.max(by: { dailyTotals[$0] < dailyTotals[$1] }), r.weekSum > 0 {
            r.heaviest = days[maxIdx].full
            r.heaviestTokens = dailyTotals[maxIdx]
        }
        if let top = modelTotals.max(by: { $0.value < $1.value }) {
            r.topModel = ModelMeta.info(top.key).label
            r.topModelPct = activeTotal > 0 ? Int((top.value / activeTotal * 100).rounded()) : 0
        }
        if let topP = projectTotals.max(by: { $0.value < $1.value }) {
            r.topProject = topP.key.split(separator: "/").last.map(String.init) ?? "n/a"
        }
        return r
    }

    private static func num(_ any: Any?) -> Double {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        return 0
    }
}
