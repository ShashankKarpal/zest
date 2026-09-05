import Foundation

// One `system_profiler SPBluetoothDataType -json` for the whole app. DevicesService and
// PresenceService both refresh every 30 s and used to run their own copy of that command,
// so the Bluetooth stack was walked twice per cycle (audit Z-B7). Callers share a snapshot
// that is at most `ttl` old; concurrent callers wait for the single run in flight.
final class BluetoothInventory {
    static let shared = BluetoothInventory()

    typealias Fetcher = () -> [String: Any]?

    private let ttl: TimeInterval
    private let fetch: Fetcher
    private let queue = DispatchQueue(label: "com.shanky.zest.bluetooth-inventory")
    private var cached: [String: Any]?
    private var fetchedAt: Date = .distantPast
    private(set) var fetchCount = 0

    init(ttl: TimeInterval = 30,
         fetch: @escaping Fetcher = { Shell.runJSON("/usr/sbin/system_profiler SPBluetoothDataType -json", timeout: 15) }) {
        self.ttl = ttl
        self.fetch = fetch
    }

    // Returns the cached profile when fresh, otherwise fetches once. Serialized, so two
    // services asking at the same moment cost one system_profiler run, not two.
    func snapshot(now: Date = Date()) -> [String: Any]? {
        queue.sync {
            if let c = cached, now.timeIntervalSince(fetchedAt) < ttl { return c }
            fetchCount += 1
            let fresh = fetch()
            if fresh != nil { cached = fresh; fetchedAt = now }
            return fresh ?? cached
        }
    }
}
