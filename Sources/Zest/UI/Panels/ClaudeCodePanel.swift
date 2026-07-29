import SwiftUI

// Claude Code usage / cost tracker. Same merged ccusage1+ccusage2 (+ M1 mirror) pipeline
// as the original CoffeeScript widget: today tokens/cost, per-machine per-account split
// (M1/M4 x kk1/kk2 with jsonl ping counts), API-equivalent blended rate, and the
// today/month/lifetime ledger.
struct ClaudeCodePanel: View {
    @ObservedObject var runner: WidgetPanelRunner

    var body: some View {
        let d = JDict(runner.json)
        if d.isEmpty {
            LoadingCard(text: "Loading Claude Code usage...")
        } else if d.s("status") == "error" {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Badge(text: "CLAUDE CODE", color: Theme.green2)
                    Text("!").font(.system(size: 35, weight: .bold)).foregroundColor(Theme.text)
                    Text(d.s("message")).font(.system(size: 13)).foregroundColor(Theme.dim)
                }
            }.frame(width: 344)
        } else {
            content(d)
        }
    }

    private func content(_ d: JDict) -> some View {
        let rate = d.d("lifeTok") > 0 ? d.d("lifeCost") / d.d("lifeTok") * 1e6 : 0
        return Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Badge(text: "CLAUDE CODE", color: Theme.green2)
                    Spacer()
                    Text("Updated \(ago(d.d("ts")))").font(.system(size: 11)).foregroundColor(Theme.faint)
                }.padding(.bottom, 12)

                Text(Fmt.tokens(d.d("todayTok"))).font(.system(size: 35, weight: .bold)).foregroundColor(Theme.text)
                Text("tokens today · \(d.s("today")) · \(Fmt.money(d.d("todayCost")))").font(.system(size: 13)).foregroundColor(Theme.dim).padding(.top, 5)

                VStack(spacing: 3) {
                    splitRow("M1 kk1", d.d("m1kk1Tok"), d.i("m1kk1S"))
                    splitRow("M1 kk2", d.d("m1kk2Tok"), d.i("m1kk2S"))
                    splitRow("M4 kk1", d.d("m4kk1Tok"), d.i("m4kk1S"))
                    splitRow("M4 kk2", d.d("m4kk2Tok"), d.i("m4kk2S"))
                }.padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Theme.tileBG).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))).padding(.top, 10)

                HStack {
                    Text("API-EQUIVALENT VALUE").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundColor(Theme.faint)
                    Spacer()
                    Text("\(Fmt.money(rate)) / 1M").font(.system(size: 13, weight: .bold)).foregroundColor(Theme.green2)
                }.padding(.top, 15).padding(.bottom, 4)

                VStack(spacing: 0) {
                    ledgerRow("Today", d.d("todayTok"), d.d("todayCost"))
                    ledgerRow("This month", d.d("mtdTok"), d.d("mtdCost"))
                    ledgerRow("Lifetime", d.d("lifeTok"), d.d("lifeCost"), highlight: true)
                }.overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }.padding(.top, 6)

                Text("includes cache read · both accounts · M1 + M4 · CLI only")
                    .font(.system(size: 10)).foregroundColor(Theme.ghost).frame(maxWidth: .infinity)
                    .padding(.top, 12).overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            }
        }.frame(width: 344)
    }

    private func splitRow(_ k: String, _ tok: Double, _ pings: Int) -> some View {
        HStack {
            Text(k).font(.system(size: 11)).foregroundColor(Theme.dim)
            Spacer()
            Text("\(Fmt.tokens(tok)) tok · \(pings) ping\(pings == 1 ? "" : "s")").font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.text.opacity(0.85))
        }
    }

    private func ledgerRow(_ k: String, _ tok: Double, _ cost: Double, highlight: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).font(.system(size: 12)).foregroundColor(Theme.text.opacity(0.75))
            Spacer()
            Text(Fmt.tokens(tok)).font(.system(size: 11)).foregroundColor(Theme.faint)
            Text(Fmt.money(cost)).font(.system(size: 13, weight: .semibold)).foregroundColor(highlight ? Theme.green2 : Theme.text).frame(width: 64, alignment: .trailing)
        }.padding(.vertical, 8).overlay(alignment: .bottom) { if !highlight { Rectangle().fill(Theme.hairline).frame(height: 1) } }
    }

    private func ago(_ ts: Double) -> String {
        if ts <= 0 { return "just now" }
        let s = max(0, Int(Date().timeIntervalSince1970 - ts))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s/60)m ago" }
        return "\(s/3600)h ago"
    }
}
