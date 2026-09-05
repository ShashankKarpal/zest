import Foundation

// Fixed-zone keys for on-disk history. Energy buckets and daily health samples used to be
// keyed with DateFormatter in the Mac's current locale and zone (audit Z-B9), so a
// timezone change (this Mac moves from +05:30 to +04:00 on 2026-09-15) would have shifted
// every bucket by ninety minutes and a locale change could have altered the key text
// itself. Everything here is UTC and POSIX, so a key means the same instant on any day in
// any city. Formatters are not thread-safe for concurrent mutation but are safe for
// concurrent formatting once configured; these are never mutated after creation.
enum TimeKeys {
    static let utc = TimeZone(identifier: "UTC")!

    private static func formatter(_ format: String, zone: TimeZone = utc) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = format
        return f
    }

    private static let hour = formatter("yyyy-MM-dd-HH")
    private static let day = formatter("yyyy-MM-dd")
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = utc
        return f
    }()

    static func hourKey(_ date: Date = Date()) -> String { hour.string(from: date) }
    static func dayKey(_ date: Date = Date()) -> String { day.string(from: date) }
    static func date(fromHourKey key: String) -> Date? { hour.date(from: key) }
    static func date(fromDayKey key: String) -> Date? { day.date(from: key) }
    static func iso8601(_ date: Date = Date()) -> String { iso.string(from: date) }

    // One-time migration of a key written in some other zone: read it as a wall-clock hour
    // in `zone`, re-key the same instant in UTC. A +05:30 hour straddles two UTC hours; the
    // bucket start wins, so 09:00 IST becomes the 03 UTC bucket.
    static func hourKey(rekeying legacyKey: String, from zone: TimeZone) -> String? {
        guard let d = formatter("yyyy-MM-dd-HH", zone: zone).date(from: legacyKey) else { return nil }
        return hourKey(d)
    }
}
