import SwiftUI

// Command Center > Alerts: the last 50 alerts Zest raised, newest first, with the ones
// quiet hours swallowed marked so a missed nudge can be checked after the fact.
struct AlertHistoryView: View {
    @ObservedObject var history: AlertHistory

    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHead(label: "RECENT ALERTS", right: history.entries.isEmpty ? nil : "\(history.entries.count)")
                if !history.entries.isEmpty {
                    Button("Clear") { history.clear() }.buttonStyle(.bordered).font(.system(size: 11))
                }
            }
            if history.entries.isEmpty {
                Text("No alerts yet. Battery, lifecycle and device alerts land here as they fire, including any that quiet hours silenced.")
                    .font(.system(size: 11)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 6) {
                    ForEach(history.entries) { e in row(e) }
                }
            }
        }
    }

    private func row(_ e: AlertHistory.Entry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Color(hex: e.colorHex).opacity(e.suppressed ? 0.35 : 1)).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(e.title).font(.system(size: 12, weight: .semibold)).foregroundColor(e.suppressed ? Theme.dim : Theme.text)
                    if e.suppressed { Badge(text: "quiet hours", color: Theme.dim, filled: false) }
                }
                if !e.subtitle.isEmpty {
                    Text(e.subtitle).font(.system(size: 11)).foregroundColor(Theme.dim).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.relative.localizedString(for: e.date, relativeTo: Date())).font(.system(size: 10)).foregroundColor(Theme.faint)
                Text(Self.stamp.string(from: e.date)).font(.system(size: 9)).foregroundColor(Theme.ghost)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.tileBG))
    }
}
