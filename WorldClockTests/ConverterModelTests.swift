import Foundation
import Testing
@testable import WorldClock

@MainActor
struct ConverterModelTests {
    // 2026-11-05 08:26:30 UTC = 08:26 in London, 03:26 in New York, 13:56 in India.
    private let now = Date(timeIntervalSince1970: 1_793_867_190)
    private let newYork = Place(countryCode: "US", zoneID: "America/New_York")

    @Test func inputDefaultsToNowInTheSourceZone() {
        let model = ConverterModel(source: .london, target: .india, now: now)
        #expect(model.local == LocalDateTime(year: 2026, month: 11, day: 5, hour: 8, minute: 26))
        guard case .exact(let result) = model.outcome else { Issue.record("expected exact"); return }
        #expect(result.target == LocalDateTime(year: 2026, month: 11, day: 5, hour: 13, minute: 56))
    }

    @Test func nowButtonUsesTheCurrentSource() {
        let model = ConverterModel(source: .london, target: .india, now: now)
        model.source = newYork
        model.resetToNow(now)
        #expect(model.local == LocalDateTime(year: 2026, month: 11, day: 5, hour: 3, minute: 26))
    }

    @Test func choosingTheSecondOccurrenceResetsWhenInputChanges() {
        let model = ConverterModel(source: .london, target: .india, now: now)
        model.input = LocalDateTime(year: 2026, month: 10, day: 25, hour: 1, minute: 30).asIfUTC
        model.useSecondOccurrence = true
        model.input = LocalDateTime(year: 2026, month: 10, day: 25, hour: 1, minute: 45).asIfUTC
        #expect(model.useSecondOccurrence == false)
    }

    @Test func nonexistentInputIsKeptAsTyped() {
        // The floating input must hold 02:30 exactly. Nothing may move it to 03:30.
        let model = ConverterModel(source: newYork, target: .india, now: now)
        model.input = LocalDateTime(year: 2026, month: 3, day: 8, hour: 2, minute: 30).asIfUTC
        #expect(model.local.hour == 2 && model.local.minute == 30)
        guard case .doesNotExist = model.outcome else { Issue.record("expected doesNotExist"); return }
    }

    @Test func dayShiftWording() {
        #expect(Display.dayShift(1) == "next day")
        #expect(Display.dayShift(-1) == "previous day")
        #expect(Display.dayShift(2) == "2 days later")
    }
}
