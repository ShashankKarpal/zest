import Foundation

// What the menu bar button shows, reduced to the values BatteryIconRenderer reads. Equal
// values draw identical pixels, so the button is touched only when this changes.
struct MenuBarIcon: Equatable {
    // Everything the battery pill image depends on. The renderer takes this and nothing
    // else, so the comparison cannot drift from what is drawn.
    struct Glyph: Equatable {
        var percent: Int
        var isACPower: Bool
        var isCharging: Bool
        var minutesShown: Int?      // time text in place of the percent; nil shows the percent
        var hideNumber: Bool
        var darkGlyph: Bool
        var statusColors: Bool
    }
    var glyph: Glyph
    var title: String?              // Claude readout beside the pill; nil when off or unavailable

    init(snapshot: BatterySnapshot, style: MenuBarStyle, title: String?) {
        var minutes: Int? = nil
        if style.showTimeRemaining, !style.hideNumber, let m = snapshot.timeRemainingMinutes, m > 0 { minutes = m }
        glyph = Glyph(percent: snapshot.percent, isACPower: snapshot.isACPower, isCharging: snapshot.isCharging,
                      minutesShown: minutes, hideNumber: style.hideNumber, darkGlyph: style.darkGlyph,
                      statusColors: style.statusColors)
        self.title = title
    }
}

// Every AppState change asks for a redraw: about seven a minute at rest, nineteen in the
// first second, nearly always with nothing visible changed (voltage, devices, energy).
// Each new image made the menu bar re-render the item on every display (2026-10-29). This
// turns a burst of requests into one check per `interval`, and sets the image only when the
// glyph changed and the title only when the readout changed. Main thread only.
final class MenuBarIconUpdater {
    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> Void

    private let interval: TimeInterval
    private let schedule: Scheduler
    private let current: () -> MenuBarIcon
    private let setImage: (MenuBarIcon.Glyph) -> Void
    private let setTitle: (String?) -> Void
    private(set) var shown: MenuBarIcon?
    private var pending = false

    init(interval: TimeInterval = 0.25,
         schedule: @escaping Scheduler = { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) },
         current: @escaping () -> MenuBarIcon,
         setImage: @escaping (MenuBarIcon.Glyph) -> Void,
         setTitle: @escaping (String?) -> Void) {
        self.interval = interval
        self.schedule = schedule
        self.current = current
        self.setImage = setImage
        self.setTitle = setTitle
    }

    // The first request schedules one update; requests before it fires ride along, and the
    // update reads the values current at that moment.
    func setNeedsUpdate() {
        guard !pending else { return }
        pending = true
        schedule(interval) { [weak self] in
            guard let self else { return }
            self.pending = false
            self.updateNow()
        }
    }

    func updateNow() {
        let next = current()
        if next.glyph != shown?.glyph { setImage(next.glyph) }
        if shown == nil || next.title != shown?.title { setTitle(next.title) }
        shown = next
    }
}
