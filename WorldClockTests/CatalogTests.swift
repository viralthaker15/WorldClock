import Foundation
import Testing
@testable import WorldClock

/// The catalog depends on the OS tz database, so these tests check stable facts rather than exact counts.
@MainActor
struct CatalogTests {
    // Swift note: a `static let` is built once and shared across tests, like a module-level const.
    static let rows = ZoneCatalog.bundledRows()
    static let entries = ZoneCatalog.build(from: rows, locale: Locale(identifier: "en_US"))

    private func entries(in country: String) -> [ZoneEntry] {
        Self.entries.filter { $0.place.countryCode == country }
    }

    private func entry(_ zoneID: String) throws -> ZoneEntry {
        try #require(Self.entries.first { $0.place.zoneID == zoneID }, "No row for \(zoneID)")
    }

    @Test func zoneTabIsBundledAndParsed() {
        #expect(Self.rows.count > 400)
        #expect(Self.rows.contains(.init(countryCode: "GB", zoneID: "Europe/London", comment: nil)))
        #expect(Self.rows.contains(.init(countryCode: "US", zoneID: "America/New_York", comment: "Eastern (most areas)")))
    }

    @Test func everyEntryIsAZoneTheOSKnows() {
        #expect(Self.entries.count > 250)
        for entry in Self.entries {
            #expect(TimeZone(identifier: entry.place.zoneID) != nil, "\(entry.place.zoneID)")
        }
    }

    @Test func singleZoneCountriesHaveOneRow() {
        #expect(entries(in: "GB").map(\.place.zoneID) == ["Europe/London"])
        #expect(entries(in: "IN").map(\.place.zoneID) == ["Asia/Kolkata"])
    }

    @Test func usZonesAreMergedByCurrentBehaviour() throws {
        let us = entries(in: "US").map(\.city)
        #expect(us == ["New York", "Chicago", "Denver", "Phoenix", "Los Angeles", "Anchorage", "Adak", "Honolulu"])
        #expect(try entry("America/New_York").alsoCovers.contains("Detroit"))
        #expect(try entry("America/Chicago").alsoCovers.contains("Tell City"))
        // Every US row shares a flag but has its own label.
        #expect(Set(entries(in: "US").map(\.flag)) == ["🇺🇸"])
    }

    @Test func mergedGroupsAreNamedAfterTheBestKnownCity() throws {
        #expect(entries(in: "AU").map(\.city).contains("Sydney"))
        #expect(try entry("Australia/Sydney").alsoCovers.contains("Melbourne"))
        #expect(try entry("America/Sao_Paulo").alsoCovers.contains("Belem"))
        #expect(!entries(in: "AU").map(\.city).contains("Hobart"))
    }

    @Test func zoneOnYearRoundDaylightTimeIsLabelledByItsCurrentName() throws {
        // tzdata 2026 has British Columbia on permanent UTC-7. Only check while the OS data still says so.
        let vancouver = TimeZone(identifier: "America/Vancouver")!
        guard vancouver.nextDaylightSavingTimeTransition(after: Date()) == nil,
              vancouver.isDaylightSavingTime(for: Date()) else { return }
        #expect(try entry("America/Vancouver").abbreviation == "PDT")
    }

    @Test func labelsUseRealAbbreviations() throws {
        #expect(try entry("America/New_York").label == "New York (EST/EDT)")
        #expect(try entry("America/Los_Angeles").label == "Los Angeles (PST/PDT)")
        #expect(try entry("Europe/London").label == "London (GMT/BST)")
        #expect(try entry("Asia/Kolkata").label == "Kolkata (IST)")
        #expect(try entry("Asia/Tokyo").label == "Tokyo (JST)")             // no DST, so no daylight name
        #expect(try entry("America/Phoenix").label == "Phoenix (MST)")      // Arizona skips DST
        #expect(try entry("Australia/Sydney").label == "Sydney (AEST/AEDT)")
    }

    @Test(arguments: [
        ("EST", "America/New_York"),
        ("pst", "America/Los_Angeles"),
        ("IST", "Asia/Kolkata"),
        ("india", "Asia/Kolkata"),
        ("Kolkata", "Asia/Kolkata"),
        ("united kingdom", "Europe/London"),
        ("UK", "Europe/London"),
        ("london", "Europe/London"),
        ("los ang", "America/Los_Angeles"),
        ("Detroit", "America/New_York"),
        ("Sao Paulo", "America/Sao_Paulo"),
        ("São Paulo", "America/Sao_Paulo"),
        ("utc+5:30", "Asia/Kolkata"),
        ("MSK", "Europe/Moscow"),
    ])
    func searchFindsByCountryCityAndAbbreviation(query: String, zoneID: String) {
        let results = ZoneCatalog.search(Self.entries, query: query)
        #expect(results.first?.place.zoneID == zoneID, "top hits: \(results.prefix(3).map(\.label))")
    }

    @Test func searchRanksExactAbbreviationAboveWordPrefix() {
        // "IST" should list India, Ireland (GMT/IST) and Israel-style exact matches before "Istanbul".
        let results = ZoneCatalog.search(Self.entries, query: "IST").map(\.place.zoneID)
        let india = results.firstIndex(of: "Asia/Kolkata")
        let istanbul = results.firstIndex(of: "Europe/Istanbul")
        #expect(india != nil && istanbul != nil && india! < istanbul!)
        // Substrings inside words don't match: "ist" must not pull in "Pakistan".
        #expect(!results.contains("Asia/Karachi"))
    }

    @Test func emptySearchReturnsEverything() {
        #expect(ZoneCatalog.search(Self.entries, query: "  ").count == Self.entries.count)
    }

    @Test func buildIsCheapEnoughToRunOnEveryOpen() {
        let start = Date()
        _ = ZoneCatalog.build(from: Self.rows)
        let ms = Date().timeIntervalSince(start) * 1000
        print("ZoneCatalog.build took \(String(format: "%.1f", ms)) ms for \(Self.rows.count) rows")
        #expect(ms < 250)
    }

    @Test func abbreviationAtAnInstantTellsTheRepeatedHourApart() throws {
        let london = TimeZone(identifier: "Europe/London")!
        guard case .occursTwice(let first, let second) = TimeMath.convert(
            LocalDateTime(year: 2026, month: 10, day: 25, hour: 1, minute: 30), from: london, to: .gmt
        ) else { Issue.record("expected occursTwice"); return }
        #expect(ZoneCatalog.abbreviation(for: london, countryCode: "GB", at: first.instant) == "BST")
        #expect(ZoneCatalog.abbreviation(for: london, countryCode: "GB", at: second.instant) == "GMT")
        #expect(ZoneCatalog.abbreviation(for: TimeZone(identifier: "Asia/Kolkata")!, countryCode: "IN", at: Date()) == "IST")
    }

    @Test func helpers() {
        #expect(ZoneCatalog.cityName(from: "America/Argentina/Buenos_Aires") == "Buenos Aires")
        #expect(ZoneCatalog.offsetText(19_800) == "+5:30")
        #expect(ZoneCatalog.offsetText(-18_000) == "-5")
        #expect(ZoneCatalog.isOffsetName("GMT+5:30"))
        #expect(!ZoneCatalog.isOffsetName("GMT"))
    }
}
