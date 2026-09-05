import Foundation
import Combine

// The last 50 alerts Zest decided to raise, shown and suppressed alike, so a nudge that
// fired while you were away (or was silenced by quiet hours) can be checked after the
// fact. Persisted as JSON in ~/Library/Application Support/Zest/alerts-history.json.
final class AlertHistory: ObservableObject {
    struct Entry: Codable, Identifiable, Equatable {
        var id: UUID = UUID()
        var ts: Double                 // seconds since 1970, UTC
        var title: String
        var subtitle: String
        var colorHex: UInt32
        var suppressed: Bool           // true when quiet hours swallowed it
        var date: Date { Date(timeIntervalSince1970: ts) }
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
        entries.insert(Entry(ts: date.timeIntervalSince1970, title: title, subtitle: subtitle,
                             colorHex: colorHex, suppressed: suppressed), at: 0)
        if entries.count > Self.capacity { entries.removeLast(entries.count - Self.capacity) }
        save()
    }

    func clear() { entries = []; save() }

    // Pure trimming rule, exposed for tests.
    static func trimmed(_ list: [Entry]) -> [Entry] {
        let sorted = list.sorted { $0.ts > $1.ts }
        return Array(sorted.prefix(capacity))
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
