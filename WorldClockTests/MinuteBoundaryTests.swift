import Foundation
import Testing
@testable import WorldClock

struct MinuteBoundaryTests {
    private let noon = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-15 08:00:00 UTC, on a minute boundary

    @Test(arguments: [0.0, 0.001, 12.5, 59.0, 59.999])
    func firesJustAfterTheNextMinute(secondsIntoMinute: Double) {
        let next = MinuteBoundary.next(after: noon.addingTimeInterval(secondsIntoMinute))
        #expect(next == noon.addingTimeInterval(60 + MinuteBoundary.margin))
    }

    @Test func isAlwaysInTheFutureAndWithinAMinute() {
        // Arbitrary times, e.g. after waking from a sleep of any length.
        for offset in stride(from: 0.0, to: 7_200, by: 7.3) {
            let now = noon.addingTimeInterval(offset)
            let wait = MinuteBoundary.next(after: now).timeIntervalSince(now)
            #expect(wait > 0 && wait <= 60 + MinuteBoundary.margin)
        }
    }

    @Test func boundaryIsAMinuteChangeInHalfHourAndQuarterHourZones() {
        let next = MinuteBoundary.next(after: noon.addingTimeInterval(30)).addingTimeInterval(-MinuteBoundary.margin)
        for id in ["Asia/Kolkata", "Asia/Kathmandu", "Australia/Eucla", "America/St_Johns"] {
            let seconds = Calendar.current.dateComponents(in: TimeZone(identifier: id)!, from: next).second
            #expect(seconds == 0, "\(id)")
        }
    }
}
