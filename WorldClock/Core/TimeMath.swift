import Foundation

// Everything in Core/ is pure logic. `nonisolated` opts these types out of the project's
// default "everything runs on the main actor" rule, so tests (and any thread) can call them.
// All offsets and DST rules come from Foundation's TimeZone (the OS tz database). Nothing is hard-coded.

/// A wall-clock date and time with no timezone attached. JS equivalent: `Temporal.PlainDateTime`.
///
/// Swift note: a `struct` is a value type. Assigning it copies it, like a frozen object literal.
/// `Hashable` and `Sendable` are protocols the compiler derives for free. They give you `==`,
/// use as a dictionary key, and permission to pass the value between threads.
nonisolated struct LocalDateTime: Hashable, Sendable, CustomStringConvertible {
    var year: Int
    var month: Int
    var day: Int
    var hour: Int
    var minute: Int

    var description: String {
        String(format: "%04d-%02d-%02d %02d:%02d", year, month, day, hour, minute)
    }

    /// The instant you'd get if this wall-clock time were in UTC. Used as a reference point for
    /// working out what it means in a real zone. Out-of-range fields roll over, e.g. Feb 30 -> Mar 2.
    var asIfUTC: Date {
        TimeMath.utcCalendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: 0
        ))!
    }

    /// The wall-clock reading at `instant` in `zone`.
    init(_ instant: Date, in zone: TimeZone) {
        self.init(instant, offset: zone.secondsFromGMT(for: instant))
    }

    /// The wall-clock reading at `instant` under a fixed offset from GMT, in seconds.
    init(_ instant: Date, offset: Int) {
        let shifted = instant.addingTimeInterval(TimeInterval(offset))
        let c = TimeMath.utcCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: shifted)
        self.init(year: c.year!, month: c.month!, day: c.day!, hour: c.hour!, minute: c.minute!)
    }

    init(year: Int, month: Int, day: Int, hour: Int, minute: Int) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
    }

    /// Whole calendar days from `other`'s date to this one's date, ignoring the time of day.
    func calendarDays(since other: LocalDateTime) -> Int {
        let a = LocalDateTime(year: other.year, month: other.month, day: other.day, hour: 0, minute: 0).asIfUTC
        let b = LocalDateTime(year: year, month: month, day: day, hour: 0, minute: 0).asIfUTC
        return Int((b.timeIntervalSince(a) / 86_400).rounded())
    }
}

/// A wall-clock time that maps to a real instant, together with what that instant reads as in the target zone.
nonisolated struct ConvertedTime: Equatable, Sendable {
    let instant: Date
    /// The source zone's offset from GMT at `instant`, in seconds. It tells the two halves of a repeated hour apart.
    let sourceOffset: Int
    let target: LocalDateTime
    let targetOffset: Int
}

/// Clocks jumped forward, so a range of wall-clock times never happened.
nonisolated struct Gap: Equatable, Sendable {
    /// The instant the clocks jumped.
    let transition: Date
    let offsetBefore: Int
    let offsetAfter: Int

    /// The wall-clock reading the clocks jumped from, e.g. 02:00.
    var localStart: LocalDateTime { LocalDateTime(transition, offset: offsetBefore) }

    /// The wall-clock reading the clocks jumped to, e.g. 03:00.
    var localEnd: LocalDateTime { LocalDateTime(transition, offset: offsetAfter) }
}

/// Swift note: this is like a TypeScript discriminated union,
/// `{ kind: "exact", value } | { kind: "occursTwice", first, second } | { kind: "doesNotExist", gap }`.
/// A `switch` over it must handle every case, or the code doesn't compile.
nonisolated enum ConversionOutcome: Equatable, Sendable {
    case exact(ConvertedTime)
    /// Clocks went back, so this wall-clock time happened twice. `first` is the earlier instant.
    case occursTwice(first: ConvertedTime, second: ConvertedTime)
    /// Clocks went forward over this wall-clock time, so it never happened.
    case doesNotExist(Gap)
}

nonisolated enum TimeMath {
    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// Every instant at which `zone`'s clocks read `local`: zero, one or two of them.
    ///
    /// Method: for each GMT offset in use within a day either side, assume that offset applies and
    /// get a candidate instant. Keep the candidate only if the zone really uses that offset then.
    /// Real offsets are within ±14 h, so ±1 day covers the offset before and after any nearby transition.
    static func instants(for local: LocalDateTime, in zone: TimeZone) -> [Date] {
        let reference = local.asIfUTC
        let offsets = Set([-86_400.0, 0, 86_400].map {
            zone.secondsFromGMT(for: reference.addingTimeInterval($0))
        })
        return offsets
            .map { reference.addingTimeInterval(TimeInterval(-$0)) }
            .filter { candidate in
                let offset = zone.secondsFromGMT(for: candidate)
                return candidate.addingTimeInterval(TimeInterval(offset)) == reference
            }
            .sorted()
    }

    /// Converts a wall-clock time in `source` to the wall-clock time in `target`.
    /// The input is never moved silently: an ambiguous or skipped time is reported as such.
    static func convert(_ local: LocalDateTime, from source: TimeZone, to target: TimeZone) -> ConversionOutcome {
        let matches = instants(for: local, in: source).map { instant in
            ConvertedTime(
                instant: instant,
                sourceOffset: source.secondsFromGMT(for: instant),
                target: LocalDateTime(instant, in: target),
                targetOffset: target.secondsFromGMT(for: instant)
            )
        }
        switch matches.count {
        case 1:
            return .exact(matches[0])
        case 2...:
            return .occursTwice(first: matches[0], second: matches[matches.count - 1])
        default:
            return .doesNotExist(gap(around: local.asIfUTC, in: source))
        }
    }

    /// Finds the forward jump that swallowed a wall-clock time. `reference` is that time read as if it were UTC.
    static func gap(around reference: Date, in zone: TimeZone) -> Gap {
        // The jump is between these two instants: one before the skipped time could be reached, one after.
        var low = reference.addingTimeInterval(-86_400)
        var high = reference.addingTimeInterval(86_400)
        let before = zone.secondsFromGMT(for: low)
        // Binary search to the second at which the offset changes (17 steps for one day).
        while high.timeIntervalSince(low) > 1 {
            let mid = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
            if zone.secondsFromGMT(for: mid) == before { low = mid } else { high = mid }
        }
        // tz transitions fall on whole seconds, and the transition t satisfies low < t <= high <= low + 1.
        // The only whole second in that range is floor(low) + 1.
        let transition = Date(timeIntervalSinceReferenceDate: low.timeIntervalSinceReferenceDate.rounded(.down) + 1)
        return Gap(transition: transition, offsetBefore: before, offsetAfter: zone.secondsFromGMT(for: transition))
    }
}
