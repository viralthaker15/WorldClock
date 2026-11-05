import Foundation

nonisolated enum MinuteBoundary {
    /// How long after the boundary to fire. The time is read when the timer fires, so this margin
    /// ensures the new minute is shown even if the timer fires a few ms early.
    static let margin: TimeInterval = 0.05

    /// The next time, strictly after `now`, at which the minute changes, plus `margin`.
    ///
    /// UTC minutes are also local minutes in every zone in use today, because all current offsets are whole
    /// minutes. So one boundary works whichever zone the menu bar shows.
    static func next(after now: Date) -> Date {
        let seconds = now.timeIntervalSince1970
        return Date(timeIntervalSince1970: ((seconds / 60).rounded(.down) + 1) * 60 + margin)
    }
}
