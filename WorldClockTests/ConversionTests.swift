import Foundation
import Testing
@testable import WorldClock

private func zone(_ id: String) -> TimeZone { TimeZone(identifier: id)! }
private let ist = zone("Asia/Kolkata")

private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> LocalDateTime {
    LocalDateTime(year: y, month: mo, day: d, hour: h, minute: mi)
}

/// One row of the spec's table. `CustomTestStringConvertible` controls how it's named in test output.
struct ConversionCase: Sendable, CustomTestStringConvertible {
    let zoneID: String
    let local: LocalDateTime
    let expectedIST: LocalDateTime

    var testDescription: String { "\(zoneID) \(local) -> \(expectedIST) IST" }
}

struct ConversionTests {
    // Required cases from the spec. Swift Testing runs one test per argument (like Jest's `test.each`).
    @Test(arguments: [
        ConversionCase(zoneID: "Europe/London", local: at(2026, 1, 15, 10, 0), expectedIST: at(2026, 1, 15, 15, 30)),
        ConversionCase(zoneID: "Europe/London", local: at(2026, 7, 15, 10, 0), expectedIST: at(2026, 7, 15, 14, 30)),
        ConversionCase(zoneID: "America/New_York", local: at(2026, 1, 15, 9, 0), expectedIST: at(2026, 1, 15, 19, 30)),
        ConversionCase(zoneID: "America/New_York", local: at(2026, 7, 15, 9, 0), expectedIST: at(2026, 7, 15, 18, 30)),
        ConversionCase(zoneID: "America/New_York", local: at(2026, 1, 15, 20, 0), expectedIST: at(2026, 1, 16, 6, 30)),
    ])
    func convertsToIST(_ c: ConversionCase) throws {
        let outcome = TimeMath.convert(c.local, from: zone(c.zoneID), to: ist)
        guard case .exact(let result) = outcome else {
            Issue.record("Expected an exact conversion, got \(outcome)")
            return
        }
        #expect(result.target == c.expectedIST)
    }

    @Test func newYorkEveningLandsOnNextDayInIndia() throws {
        let source = at(2026, 1, 15, 20, 0)
        guard case .exact(let result) = TimeMath.convert(source, from: zone("America/New_York"), to: ist) else {
            Issue.record("Expected exact"); return
        }
        #expect(result.target.calendarDays(since: source) == 1)
    }

    @Test func springForwardTimeIsFlaggedAsNonexistent() throws {
        // US clocks jump from 02:00 EST to 03:00 EDT on 8 March 2026.
        let outcome = TimeMath.convert(at(2026, 3, 8, 2, 30), from: zone("America/New_York"), to: ist)
        guard case .doesNotExist(let gap) = outcome else {
            Issue.record("Expected doesNotExist, got \(outcome)"); return
        }
        #expect(gap.localStart == at(2026, 3, 8, 2, 0))
        #expect(gap.localEnd == at(2026, 3, 8, 3, 0))
        #expect(gap.offsetBefore == -5 * 3600)
        #expect(gap.offsetAfter == -4 * 3600)
    }

    @Test func fallBackTimeIsFlaggedAsOccurringTwice() throws {
        // UK clocks go back from 02:00 BST to 01:00 GMT on 25 October 2026, so 01:30 happens twice.
        let outcome = TimeMath.convert(at(2026, 10, 25, 1, 30), from: zone("Europe/London"), to: ist)
        guard case .occursTwice(let first, let second) = outcome else {
            Issue.record("Expected occursTwice, got \(outcome)"); return
        }
        #expect(first.instant < second.instant)
        #expect(first.sourceOffset == 3600)   // 01:30 BST
        #expect(second.sourceOffset == 0)     // 01:30 GMT
        #expect(first.target == at(2026, 10, 25, 6, 0))
        #expect(second.target == at(2026, 10, 25, 7, 0))
    }

    @Test func timesNextToTransitionsAreOrdinary() {
        // One minute either side of each change must not be flagged.
        let ny = zone("America/New_York"), london = zone("Europe/London")
        for (local, tz) in [(at(2026, 3, 8, 1, 59), ny), (at(2026, 3, 8, 3, 0), ny),
                            (at(2026, 10, 25, 0, 59), london), (at(2026, 10, 25, 2, 0), london)] {
            guard case .exact = TimeMath.convert(local, from: tz, to: ist) else {
                Issue.record("\(local) in \(tz.identifier) should be exact"); continue
            }
        }
    }

    @Test func convertingIntoTheSameZoneIsIdentity() {
        let local = at(2026, 7, 15, 9, 0)
        guard case .exact(let r) = TimeMath.convert(local, from: ist, to: ist) else {
            Issue.record("Expected exact"); return
        }
        #expect(r.target == local)
    }

    @Test @MainActor func converterTargetDefaultsToIndia() throws {
        let defaults = try #require(UserDefaults(suiteName: "WorldClockTests.\(UUID())"))
        let settings = AppSettings(defaults: defaults)
        #expect(settings.converterTarget == Place(countryCode: "IN", zoneID: "Asia/Kolkata"))
        #expect(settings.menuBarPlace == .london)

        settings.menuBarPlace = Place(countryCode: "US", zoneID: "America/New_York")
        #expect(AppSettings(defaults: defaults).menuBarPlace.zoneID == "America/New_York")

        defaults.set(["countryCode": "US", "zoneID": "Not/AZone"], forKey: "menuBarPlace")
        #expect(settings.menuBarPlace == .london)
    }

    @Test func flagsAreBuiltFromRegionalIndicators() {
        #expect(Place.flag(for: "GB") == "🇬🇧")
        #expect(Place.flag(for: "us") == "🇺🇸")
        #expect(Place.flag(for: "IN") == "🇮🇳")
    }
}
