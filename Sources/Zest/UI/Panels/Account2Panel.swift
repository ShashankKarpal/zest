import SwiftUI

// Account 2 (secondary account). Recreates the widget card from the same fetch.py + cc
// JSON: cu (Claude Usage plist), hasExtra, cc (ccusage2 ledger), cb (active block tokens).
struct Account2Panel: View {
    @ObservedObject var runner: WidgetPanelRunner

    private let activeDays = [2, 3, 4, 5, 6]   // Tue..Sat, matches ACTIVE_DAYS

    var body: some View {
        let root = JDict(runner.json)
        let cu = root.obj("cu")
        if root.isEmpty || cu.isEmpty {
            LoadingCard(text: "Waiting for Claude Usage...")
        } else {
            content(root, cu)
        }
    }

    private func content(_ root: JDict, _ cu: JDict) -> some View {
        let sessionPct = cu.d("sessionPercentage")
        let weeklyPct = cu.d("weeklyPercentage")
        let cb = root.d("cb")
        let now = Date()
        let sessionReset = TimeFmt.fromCocoa(cu.d("sessionResetTime"))
        let weeklyReset = TimeFmt.fromCocoa(cu.d("weeklyResetTime"))
        let weekStart = weeklyReset.addingTimeInterval(-7 * 86400)

        let exp = expectedPct(weekStart: weekStart, weekEnd: weeklyReset, now: now)
        let paceDelta = Int((weeklyPct - exp).rounded())
        let zone = paceZone(paceDelta)
        let dayElapsed = min(7, max(0, Int(now.timeIntervalSince(weekStart) / 86400)))

        let opusPct = cu.d("opusWeeklyPercentage"), sonnetPct = cu.d("sonnetWeeklyPercentage")
        let opusTok = cu.d("opusWeeklyTokensUsed"), sonnetTok = cu.d("sonnetWeeklyTokensUsed")
        let weeklyUsed = cu.d("weeklyTokensUsed"), weeklyLimit = max(1, cu.d("weeklyLimit", 1_000_000))
        let costUsed = cu.d("costUsed") / 100, costLimit = cu.d("costLimit") / 100
        let costPct = costLimit > 0 ? costUsed / costLimit * 100 : 0
        let costColor = Theme.gaugeColor(costPct)
        let sym = cu.s("costCurrency", "USD") == "USD" ? "$" : cu.s("costCurrency") + " "

        let cc = root.obj("cc")
        let ccHas = cc.has("lifeTok")
        let ccRate = cc.d("lifeTok") > 0 ? cc.d("lifeCost") / cc.d("lifeTok") * 1e6 : 0

        let sessionColor = Theme.gaugeColor(sessionPct)
        let weeklyColor = Theme.gaugeColor(weeklyPct)

        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Badge(text: "Account 2", color: Theme.green)
                    Badge(text: "Max 5x", color: Theme.dim, filled: false)
                    Spacer()
                    Text(updatedText(cu)).font(.system(size: 10)).foregroundColor(Theme.faint)
                }

                VStack(spacing: 2) {
                    Text(TimeFmt.countdown(sessionReset)).font(.system(size: 34, weight: .regular)).foregroundColor(Theme.amber)
                    Text("UNTIL SESSION RESET").font(.system(size: 9)).tracking(1.5).foregroundColor(Theme.faint)
                    Text(TimeFmt.clock(sessionReset)).font(.system(size: 10)).foregroundColor(Theme.dim)
                }.frame(maxWidth: .infinity).padding(.vertical, 6)

                HStack(spacing: 10) {
                    Tile(label: "SESSION", value: Fmt.pct(sessionPct), color: sessionColor, sub: "\(Fmt.tokens(cb)) cli tok")
                    Tile(label: "WEEKLY", value: Fmt.pct(weeklyPct), color: weeklyColor, sub: "\(Fmt.tokens(weeklyUsed)) tok")
                }

                paceRow("Session", sessionPct, sessionColor)
                paceRow("Weekly", weeklyPct, weeklyColor)

                Divider1()
                HStack {
                    SectionHead(label: "WEEKLY PACE")
                    Badge(text: zone.label, color: zone.color, filled: true)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(paceDelta > 0 ? "+" : "")\(paceDelta)%").font(.system(size: 24, weight: .semibold)).foregroundColor(zone.color)
                    Text("\(paceDelta < 0 ? "below" : "above") expected (\(Int(exp.rounded()))%)").font(.system(size: 10)).foregroundColor(Theme.dim)
                }
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2).fill(i < dayElapsed ? zone.color : Color.white.opacity(0.08)).frame(height: 5)
                    }
                }
                Text("Day \(dayElapsed) of 7 this window").font(.system(size: 9)).foregroundColor(Theme.faint)

                Divider1()
                SectionHead(label: "WEEKLY TOKENS", right: "\(Fmt.tokens(weeklyUsed)) / \(Fmt.tokens(weeklyLimit))", rightColor: Theme.green)
                MeterBar(pct: weeklyUsed / weeklyLimit * 100, color: weeklyColor, height: 8)
                HStack {
                    LegendDot(color: Theme.amber, label: "Opus \(Int(opusPct))%", value: Fmt.tokens(opusTok))
                    Spacer()
                    LegendDot(color: Theme.blue, label: "Sonnet \(Int(sonnetPct))%", value: Fmt.tokens(sonnetTok))
                }

                Divider1()
                SectionHead(label: "EXTRA CREDIT / COST", right: "\(sym)\(String(format: "%.2f", costUsed))", rightColor: costColor)
                MeterBar(pct: costPct, color: costColor, height: 8)
                HStack {
                    Text("\(sym)\(String(format: "%.2f", max(0, costLimit - costUsed))) left of \(sym)\(String(format: "%.0f", costLimit)) (\(Int(costPct.rounded()))%)")
                        .font(.system(size: 10)).foregroundColor(Theme.dim)
                    Spacer()
                    Text("extra \(root.b("hasExtra") ? "ON" : "off")").font(.system(size: 9, weight: .semibold))
                        .foregroundColor(root.b("hasExtra") ? Theme.green : Theme.faint)
                }

                if ccHas {
                    Divider1()
                    SectionHead(label: "API-EQUIVALENT VALUE", right: "\(Fmt.money(ccRate)) / 1M", rightColor: Theme.green)
                    ledgerRow("Today", cc.d("todayTok"), cc.d("todayCost"))
                    ledgerRow("This month", cc.d("mtdTok"), cc.d("mtdCost"))
                    ledgerRow("Lifetime", cc.d("lifeTok"), cc.d("lifeCost"), highlight: true)

                    Divider1()
                    SectionHead(label: "CLI RAW · CCUSAGE2", right: Fmt.tokens(cc.d("weekTok")), rightColor: Theme.green)
                    Text("includes cache read · M1 + M4 · acct 2").font(.system(size: 9)).foregroundColor(Theme.ghost)
                    HStack(alignment: .firstTextBaseline) {
                        Text("TODAY").font(.system(size: 9)).tracking(1.5).foregroundColor(Theme.faint)
                        Text(Fmt.tokens(cc.d("todayTok"))).font(.system(size: 20, weight: .semibold)).foregroundColor(Theme.text)
                        Spacer()
                        let delta = cc.d("todayTok") - cc.d("prevTok")
                        Text("\(delta >= 0 ? "↑" : "↓") \(Fmt.tokens(abs(delta))) vs prev day").font(.system(size: 10)).foregroundColor(Theme.dim)
                    }
                    RawCCLegend(models: cc.objArr("models"))
                }

                Divider1()
                Text("Weekly resets in \(TimeFmt.countdown(weeklyReset)) (\(TimeFmt.clock(weeklyReset)))")
                    .font(.system(size: 10)).foregroundColor(Theme.faint).frame(maxWidth: .infinity)
            }
        }.frame(width: 344)
    }

    private func ledgerRow(_ k: String, _ tok: Double, _ cost: Double, highlight: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).font(.system(size: 12)).foregroundColor(Theme.text.opacity(0.75))
            Spacer()
            Text(Fmt.tokens(tok)).font(.system(size: 11)).foregroundColor(Theme.faint)
            Text(Fmt.money(cost)).font(.system(size: 13, weight: .semibold)).foregroundColor(highlight ? Theme.green2 : Theme.text)
                .frame(width: 64, alignment: .trailing)
        }.padding(.vertical, 6).overlay(alignment: .bottom) { if !highlight { Rectangle().fill(Theme.hairline).frame(height: 1) } }
    }

    private func paceRow(_ label: String, _ pct: Double, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 11)).foregroundColor(Theme.dim).frame(width: 52, alignment: .leading)
            MeterBar(pct: pct, color: color, height: 4)
            Text(Fmt.pct(pct)).font(.system(size: 11)).foregroundColor(Theme.dim).frame(width: 36, alignment: .trailing)
        }
    }

    private func updatedText(_ cu: JDict) -> String {
        guard cu.has("lastUpdated") else { return "" }
        let d = TimeFmt.fromCocoa(cu.d("lastUpdated"))
        let m = max(0, Int(Date().timeIntervalSince(d) / 60))
        return m == 0 ? "Updated just now" : "Updated \(m)m ago"
    }

    // Workweek-aware expected % (15-min steps over active days), matches the widget.
    private func expectedPct(weekStart: Date, weekEnd: Date, now: Date) -> Double {
        let step: TimeInterval = 15 * 60
        var total = 0.0, elapsed = 0.0
        let activeSet = Set(activeDays.map { ($0 - 1 + 7) % 7 })
        let cal = Calendar.current
        var t = weekStart.timeIntervalSince1970
        let end = weekEnd.timeIntervalSince1970
        while t < end {
            let d = Date(timeIntervalSince1970: t)
            let weekday = cal.component(.weekday, from: d) - 1   // 0=Sun
            if activeSet.contains(weekday) {
                total += step
                if t < now.timeIntervalSince1970 { elapsed += step }
            }
            t += step
        }
        return total == 0 ? 0 : elapsed / total * 100
    }

    private func paceZone(_ delta: Int) -> (label: String, color: Color) {
        if delta <= -15 { return ("Chill", Theme.green) }
        if delta <= 5 { return ("On pace", Theme.sky) }
        if delta <= 20 { return ("Warm", Theme.amber) }
        return ("Hot", Theme.red)
    }
}

struct RawCCLegend: View {
    let models: [JDict]
    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(models.enumerated()), id: \.offset) { _, m in
                let fam = ModelMeta.family(m.s("name"))
                LegendDot(color: ModelMeta.info(fam).color, label: ModelMeta.ccLabel(m.s("name")), value: Fmt.tokens(m.d("total")), square: true)
            }
        }
    }
}
