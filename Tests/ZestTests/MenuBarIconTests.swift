import XCTest
@testable import Zest

// The 2026-10-29 menu bar flicker round: the icon is set only when what it shows changes,
// and a burst of change signals costs one check. Before, every AppState change built and
// set a new image (100 changes, 100 image sets).
final class MenuBarIconTests: XCTestCase {
    // Runs scheduled work by hand, so coalescing is checked without waiting.
    private final class ManualScheduler {
        var queued: [() -> Void] = []
        func schedule(_ delay: TimeInterval, _ work: @escaping () -> Void) { queued.append(work) }
        func runAll() { let q = queued; queued.removeAll(); q.forEach { $0() } }
    }

    private final class Harness {
        let scheduler = ManualScheduler()
        var snapshot = BatterySnapshot()
        var style = MenuBarStyle()
        var title: String? = nil
        var images: [MenuBarIcon.Glyph] = []
        var titles: [String?] = []
        lazy var updater = MenuBarIconUpdater(
            schedule: { [unowned self] in self.scheduler.schedule($0, $1) },
            current: { [unowned self] in MenuBarIcon(snapshot: self.snapshot, style: self.style, title: self.title) },
            setImage: { [unowned self] in self.images.append($0) },
            setTitle: { [unowned self] in self.titles.append($0) })

        init() {
            snapshot.percent = 80
            snapshot.isACPower = true
            snapshot.voltageV = 12.6
            snapshot.amperageMA = 0
            snapshot.temperatureC = 30
        }

        // One AppState change signal, delivered the way StatusItemController delivers it.
        func change() { updater.setNeedsUpdate(); scheduler.runAll() }
    }

    func testUnchangedInputsSetNoImageAndNoTitle() {
        let h = Harness()
        h.updater.updateNow()
        XCTAssertEqual(h.images.count, 1, "the first update draws the icon")
        XCTAssertEqual(h.titles.count, 1)

        for i in 0..<100 {
            // What a battery refresh, a device scan or an energy tick changes: nothing drawn.
            h.snapshot.voltageV = 12.6 + Double(i) / 1000
            h.snapshot.amperageMA = -i
            h.snapshot.temperatureC = 30 + Double(i % 3)
            h.snapshot.adapterWatts = 94 + i % 2
            h.change()
        }
        XCTAssertEqual(h.images.count, 1, "100 change signals with the same visible inputs must set no image")
        XCTAssertEqual(h.titles.count, 1, "and no title")
    }

    func testBurstOfChangeSignalsIsOneUpdateWithTheLatestValues() {
        let h = Harness()
        h.updater.updateNow()
        for p in stride(from: 79, through: 30, by: -1) {
            h.snapshot.percent = p
            h.updater.setNeedsUpdate()
        }
        XCTAssertEqual(h.scheduler.queued.count, 1, "50 signals in a burst schedule one update")
        h.scheduler.runAll()
        XCTAssertEqual(h.images.count, 2)
        XCTAssertEqual(h.images.last?.percent, 30, "the update reads the values current when it fires")

        h.snapshot.percent = 29
        h.change()
        XCTAssertEqual(h.images.count, 3, "a signal after the burst schedules again")
    }

    func testInvalidateDrawsAgainWithUnchangedInputs() {
        let h = Harness()
        h.updater.updateNow()
        h.updater.invalidate()
        h.scheduler.runAll()
        XCTAssertEqual(h.images.count, 2, "a display change redraws the same glyph once")
        XCTAssertEqual(h.titles.count, 2)
        h.change()
        XCTAssertEqual(h.images.count, 2)
    }

    func testPercentChangeSetsTheImageOnly() {
        let h = Harness()
        h.updater.updateNow()
        h.snapshot.percent = 79
        h.change()
        XCTAssertEqual(h.images.count, 2)
        XCTAssertEqual(h.titles.count, 1)
    }

    func testReadoutChangeSetsTheTitleOnly() {
        let h = Harness()
        h.style.claudeMode = .acct1Session
        h.title = "5h 40%"
        h.updater.updateNow()
        h.title = "5h 41%"
        h.change()
        XCTAssertEqual(h.images.count, 1, "a new readout keeps the image")
        XCTAssertEqual(h.titles, ["5h 40%", "5h 41%"])
        h.title = nil
        h.change()
        XCTAssertEqual(h.titles.last, .some(nil), "losing the readout clears the title")
    }

    func testPowerAndStyleChangesRedraw() {
        let h = Harness()
        h.updater.updateNow()
        h.snapshot.isACPower = false
        h.change()
        h.snapshot.isCharging = true
        h.change()
        h.style.darkGlyph = true
        h.change()
        h.style.statusColors = false
        h.change()
        h.style.hideNumber = true
        h.change()
        XCTAssertEqual(h.images.count, 6, "each visible change draws once")
    }

    func testTimeRemainingCountsOnlyWhenTheIconShowsIt() {
        let h = Harness()
        h.snapshot.timeRemainingMinutes = 120
        h.updater.updateNow()
        h.snapshot.timeRemainingMinutes = 119
        h.change()
        XCTAssertEqual(h.images.count, 1, "minutes are not drawn while the icon shows the percent")

        h.style.showTimeRemaining = true
        h.change()
        XCTAssertEqual(h.images.last?.minutesShown, 119)
        h.snapshot.timeRemainingMinutes = 118
        h.change()
        XCTAssertEqual(h.images.count, 3)

        h.style.hideNumber = true
        h.change()
        h.snapshot.timeRemainingMinutes = 117
        h.change()
        XCTAssertEqual(h.images.count, 4, "no number, so minutes are not drawn")
        XCTAssertNil(h.images.last?.minutesShown)
    }
}
