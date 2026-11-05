import Foundation
import Observation

/// State for one opening of the popover. It's created when the popover opens and released when it
/// closes, together with the zone list and every SwiftUI view. Nothing here outlives the popover.
@Observable
final class PopoverModel {
    enum Tab: Hashable { case clock, converter }

    var tab: Tab = .clock
    var clockQuery = ""
    /// Bumped every minute by MenuBarClock (no separate timer) so row times stay current while open.
    var now: Date
    private(set) var menuBarPlace: Place
    let entries: [ZoneEntry]
    let converter: ConverterModel

    private let onChooseMenuBarPlace: (Place) -> Void
    let close: () -> Void

    init(
        entries: [ZoneEntry],
        now: Date,
        menuBarPlace: Place,
        converterTarget: Place,
        onChooseMenuBarPlace: @escaping (Place) -> Void,
        close: @escaping () -> Void
    ) {
        self.entries = entries
        self.now = now
        self.menuBarPlace = menuBarPlace
        self.converter = ConverterModel(source: menuBarPlace, target: converterTarget, now: now)
        self.onChooseMenuBarPlace = onChooseMenuBarPlace
        self.close = close
    }

    deinit {
        log.debug("PopoverModel freed")  // confirms the popover's state really goes away on close
    }

    func chooseForMenuBar(_ entry: ZoneEntry) {
        menuBarPlace = entry.place
        onChooseMenuBarPlace(entry.place)
    }

    func entry(for place: Place) -> ZoneEntry? {
        entries.first { $0.place == place } ?? entries.first { $0.coveredZoneIDs.contains(place.zoneID) }
    }

    /// "London (GMT/BST)", or the city from the IANA ID if the place isn't in the list.
    func label(for place: Place) -> String {
        entry(for: place)?.label ?? ZoneCatalog.cityName(from: place.zoneID)
    }
}

@Observable
final class ConverterModel {
    var source: Place {
        didSet { useSecondOccurrence = false }
    }
    let target: Place
    var pickingSource = false
    var sourceQuery = ""

    /// The date and time typed in, stored as a "floating" value: its reading in UTC is the wall-clock time.
    /// The date pickers are told to work in UTC, so every wall-clock time can be entered, including
    /// 02:30 on a spring-forward night. A normal Date would be moved silently to 03:30 by a picker in New York time.
    var input: Date {
        didSet { useSecondOccurrence = false }
    }
    /// For a time that occurs twice: false shows the first occurrence, true shows the second.
    var useSecondOccurrence = false

    init(source: Place, target: Place, now: Date) {
        self.source = source
        self.target = target
        self.input = Self.floating(now, in: source.timeZone)
    }

    var local: LocalDateTime { LocalDateTime(input, offset: 0) }

    var outcome: ConversionOutcome {
        TimeMath.convert(local, from: source.timeZone, to: target.timeZone)
    }

    func resetToNow(_ now: Date) {
        input = Self.floating(now, in: source.timeZone)
    }

    /// The current wall-clock time in `zone`, as a floating value (seconds dropped).
    private static func floating(_ now: Date, in zone: TimeZone) -> Date {
        LocalDateTime(now, in: zone).asIfUTC
    }
}
