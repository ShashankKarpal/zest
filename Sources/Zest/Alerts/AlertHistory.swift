import Foundation
import Combine

// The last 50 alerts Zest decided to raise, shown and suppressed alike, so a nudge that
// fired while you were away (or was silenced by quiet hours) can be checked after the
// fact. Back-to-back repeats of the same alert share one row with a count, so "Charger
// connected" no longer fills the list (on 2026-10-29, 49 of the owner's 50 rows).
// Persisted as JSON in ~/Library/Application Support/Zest/alerts-history.json.
final class AlertHistory: ObservableObject {
    struct Entry: Codable, Identifiable, Equatable {
        var id: UUID = UUID()
        var ts: Double                 // seconds since 1970, UTC
        var title: String
        var subtitle: String
        var colorHex: UInt32
        var suppressed: Bool           // true when quiet hours swallowed it
        var repeats: Int?              // times this row fired; nil is once (files before v3.1.2)
        var firstTs: Double?           // when the first of those fired; nil is `ts`
        var date: Date { Date(timeIntervalSince1970: ts) }
        var times: Int { repeats ?? 1 }
        var firstDate: Date { Date(timeIntervalSince1970: firstTs ?? ts) }

        // The same alert again: what the row shows, apart from its times.
        func isRepeat(of other: Entry) -> Bool {
            title == other.title && subtitle == other.subtitle && colorHex == other.colorHex && suppressed == other.suppressed
        }
    }

    static let capacity = 50

    @Published private(set) var entries: [Entry] = []   // newest first
    private let url: URL?

    // `url` nil keeps everything in memory (tests).
    init(url: URL? = AppConfig.dir.appendingPathComponent("alerts-history.json")) {
        self.url = url
        load()
    }

    func record(title: String, subtitle: String, colorHex: UInt32, suppressed: Bool, at date: Date = Date()) {
        entries = Self.collapsed([Entry(ts: date.timeIntervalSince1970, title: title, subtitle: subtitle,
                                        colorHex: colorHex, suppressed: suppressed)] + entries)
        if entries.count > Self.capacity { entries.removeLast(entries.count - Self.capacity) }
        save()
    }

    func clear() { entries = []; save() }

    // Pure trimming rule, exposed for tests. A saved file is folded the same way as new
    // alerts are, so older files with one row per repeat shrink on load.
    static func trimmed(_ list: [Entry]) -> [Entry] {
        let sorted = list.sorted { $0.ts > $1.ts }
        return Array(collapsed(sorted).prefix(capacity))
    }

    // Folds each run of back-to-back repeats (newest first) into its newest row, which keeps
    // its id, so a row on screen stays the same row as it counts up.
    static func collapsed(_ newestFirst: [Entry]) -> [Entry] {
        var out: [Entry] = []
        for e in newestFirst {
            guard let newer = out.last, newer.isRepeat(of: e) else { out.append(e); continue }
            var row = newer
            row.repeats = newer.times + e.times
            row.firstTs = min(newer.firstTs ?? newer.ts, e.firstTs ?? e.ts)
            out[out.count - 1] = row
        }
        return out
    }

    private func load() {
        guard let url, let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = Self.trimmed(list)
    }
    private func save() {
        guard let url, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
