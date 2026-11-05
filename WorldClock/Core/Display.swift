import Foundation

/// Formats wall-clock values for display in the user's locale (12/24-hour follows System Settings).
nonisolated enum Display {
    /// "3:30 PM" or "15:30".
    static func time(_ local: LocalDateTime) -> String {
        local.asIfUTC.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: .gmt))
    }

    /// "Fri, 16 Jan 2026" (order follows the locale).
    static func date(_ local: LocalDateTime) -> String {
        local.asIfUTC.formatted(
            Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated).day().month(.abbreviated).year()
        )
    }

    /// "UTC+5:30", "UTC-5", "UTC+0".
    static func utcOffset(_ seconds: Int) -> String {
        "UTC" + ZoneCatalog.offsetText(seconds)
    }

    /// "next day", "previous day", "2 days later"...
    static func dayShift(_ days: Int) -> String {
        switch days {
        case 1: "next day"
        case -1: "previous day"
        case let d where d > 1: "\(d) days later"
        default: "\(-days) days earlier"
        }
    }
}
