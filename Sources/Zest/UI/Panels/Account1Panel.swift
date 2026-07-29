import SwiftUI

// Account 1 (TokenEater focus). Recreates the Ubersicht card 1:1 from the same JSON the
// original widget produces (shared + history + cc + cu + cb). All numbers come from the
// identical pipeline; this view only re-renders them natively.
struct Account1Panel: View {
    @ObservedObject var runner: WidgetPanelRunner

    var body: some View {
        let root = JDict(runner.json)
        if root.isEmpty {
            LoadingCard(text: "Waiting for TokenEater...")
        } else {
            content(root)
        }
    }

    private func content(_ root: JDict) -> some View {
        let shared = root.obj("shared")
        let cu = root.obj("cu")
        let cc = root.obj("cc")
        let cb = root.d("cb")
        let cached = shared.obj("cachedUsage")
        let usage = cached.obj("usage")
        let session = usage.obj("five_hour")
        let weekly = usage.obj("seven_day")

        // Prefer Claude Usage Tracker for live %, fall back to TokenEater utilization.
        let sessionPct = cu.has("sessionPercentage") ? cu.d("sessionPercentage") : session.d("utilization")
        let weeklyPct = cu.has("weeklyPercentage") ? cu.d("weeklyPercentage") : weekly.d("utilization")
        let sessionReset = cu.has("sessionResetTime") ? TimeFmt.fromCocoa(cu.d("sessionResetTime")) : parseDate(session.s("resets_at"))
        let weeklyReset = cu.has("weeklyResetTime") ? TimeFmt.fromCocoa(cu.d("weeklyResetTime")) : parseDate(weekly.s("resets_at"))

        let agg = Acct1History.aggregate(history: root.obj("history"), weeklyReset: weeklyReset)
        let sessionColor = Theme.gaugeColor(sessionPct)
        let weeklyColor = Theme.gaugeColor(weeklyPct)

        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Badge(text: "Account 1", color: Theme.green)
                    Badge(text: "Max 5x", color: Theme.dim, filled: false)
                    Spacer()
                    Text(updatedText).font(.system(size: 10)).foregroundColor(Theme.faint)
                }

                // Session reset hero
                VStack(spacing: 2) {
                    Text(TimeFmt.countdown(sessionReset)).font(.system(size: 34, weight: .regular)).foregroundColor(Theme.amber)
                    Text("UNTIL SESSION RESET").font(.system(size: 9)).tracking(1.5).foregroundColor(Theme.faint)
                    Text(TimeFmt.clock(sessionReset)).font(.system(size: 10)).foregroundColor(Theme.dim)
                }.frame(maxWidth: .infinity).padding(.vertical, 6)

                HStack(spacing: 10) {
                    Tile(label: "SESSION", value: Fmt.pct(sessionPct), color: sessionColor, sub: "\(Fmt.tokens(cb)) cli tok")
                    Tile(label: "WEEKLY", value: Fmt.pct(weeklyPct), color: weeklyColor, sub: "\(Fmt.tokens(agg.weekSum)) tok")
                }

                paceRow("Session", sessionPct, sessionColor)
                paceRow("Weekly", weeklyPct, weeklyColor)

                Divider1()
                SectionHead(label: "LAST 7 DAYS BY MODEL", right: Fmt.tokens(agg.weekSum), rightColor: Theme.green)
                ModelBars(days: agg.days, maxDaily: agg.maxDaily)
                ModelLegend(totals: agg.modelTotals)

                if cc.has("week") {
                    Divider1()
                    SectionHead(label: "CLI RAW · CCUSAGE1", right: Fmt.tokens(cc.d("week")), rightColor: Theme.green)
                    Text("includes cache read · M1 + M4 · acct 1").font(.system(size: 9)).foregroundColor(Theme.ghost)
                    HStack(alignment: .firstTextBaseline) {
                        Text("TODAY").font(.system(size: 9)).tracking(1.5).foregroundColor(Theme.faint)
                        Text(Fmt.tokens(cc.d("today"))).font(.system(size: 20, weight: .semibold)).foregroundColor(Theme.text)
                        Spacer()
                        let delta = cc.d("today") - cc.d("prev")
                        Text("\(delta >= 0 ? "↑" : "↓") \(Fmt.tokens(abs(delta))) vs prev day").font(.system(size: 10)).foregroundColor(Theme.dim)
                    }
                    CCLegend(models: cc.objArr("models"))
                }

                Divider1()
                SectionHead(label: "HISTORY (7D)", right: "\(agg.sessions) sessions", rightColor: Theme.text)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    Tile(label: "CACHE HIT", value: "\(agg.cacheHit)%", color: Theme.green, sub: "\(Fmt.tokens(agg.cacheTotal)) cached")
                    Tile(label: "AVG / SESSION", value: Fmt.tokens(agg.avgPerSession), sub: "\(Fmt.tokens(agg.activeTotal)) active")
                    Tile(label: "HEAVIEST", value: agg.heaviest, sub: "\(Fmt.tokens(agg.heaviestTokens)) tokens")
                    Tile(label: "TOP MODEL", value: agg.topModel, sub: "\(agg.topModelPct)% of total")
                }
                Tile(label: "TOP PROJECT", value: agg.topProject)

                Divider1()
                Text("Weekly resets in \(TimeFmt.countdown(weeklyReset)) (\(TimeFmt.clock(weeklyReset)))")
                    .font(.system(size: 10)).foregroundColor(Theme.faint).frame(maxWidth: .infinity)
            }
        }
        .frame(width: 344)
    }

    private var updatedText: String {
        guard let d = runner.lastUpdated else { return "" }
        let m = Int(Date().timeIntervalSince(d) / 60)
        return m == 0 ? "Updated just now" : "Updated \(m)m ago"
    }

    private func paceRow(_ label: String, _ pct: Double, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 11)).foregroundColor(Theme.dim).frame(width: 52, alignment: .leading)
            MeterBar(pct: pct, color: color, height: 4)
            Text(Fmt.pct(pct)).font(.system(size: 11)).foregroundColor(Theme.dim).frame(width: 36, alignment: .trailing)
        }
    }

    private func parseDate(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s) ?? Date()
    }
}

struct ModelBars: View {
    let days: [Acct1History.Day]
    let maxDaily: Double
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                VStack(spacing: 6) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        ForEach(ModelMeta.order.filter { (day.models[$0] ?? 0) > 0 }, id: \.self) { m in
                            Rectangle().fill(ModelMeta.info(m).color)
                                .frame(height: max(1, 104 * ((day.models[m] ?? 0) / maxDaily)))
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 104)
                    .background(Color.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 3))
                    Text(day.label).font(.system(size: 9)).foregroundColor(Theme.faint)
                }
            }
        }
    }
}

struct ModelLegend: View {
    let totals: [String: Double]
    var body: some View {
        let items = ModelMeta.order.filter { (totals[$0] ?? 0) > 0 }
        return HStack(spacing: 10) {
            if items.isEmpty { Text("no model data in window").font(.system(size: 10)).foregroundColor(Theme.faint) }
            ForEach(items, id: \.self) { m in
                LegendDot(color: ModelMeta.info(m).color, label: ModelMeta.info(m).label, value: Fmt.tokens(totals[m] ?? 0))
            }
        }
    }
}

struct CCLegend: View {
    let models: [JDict]
    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(models.enumerated()), id: \.offset) { _, m in
                let fam = ModelMeta.family(m.s("name"))
                LegendDot(color: ModelMeta.info(fam).color, label: ModelMeta.info(fam).label, value: Fmt.tokens(m.d("total")), square: true)
            }
        }
    }
}

struct LoadingCard: View {
    var text: String
    var body: some View {
        Card { Text(text).font(.system(size: 12)).foregroundColor(Theme.faint).frame(maxWidth: .infinity).padding(.vertical, 20) }
            .frame(width: 344)
    }
}
