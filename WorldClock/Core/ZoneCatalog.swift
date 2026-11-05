import Foundation

/// One row in the country list: a country plus one of its zones.
nonisolated struct ZoneEntry: Identifiable, Hashable, Sendable {
    let place: Place
    /// In the user's language, e.g. "United States".
    let countryName: String
    /// From the IANA ID, e.g. "America/Los_Angeles" -> "Los Angeles".
    let city: String
    /// zone.tab's comment for multi-zone countries, e.g. "Eastern (most areas)".
    let region: String?
    /// e.g. "EST/EDT", "IST", or "GMT+3" when the OS has no common abbreviation.
    let abbreviation: String
    /// Cities of zones merged into this one because their clocks agree from now on (e.g. Detroit -> New York).
    let alsoCovers: [String]
    /// IANA IDs of this row's zone and of every zone merged into it.
    let coveredZoneIDs: [String]
    /// Lowercased, accent-folded words and phrases the search matches against.
    let searchTokens: [String]

    var id: Place { place }
    var flag: String { place.flag }
    /// e.g. "New York (EST/EDT)".
    var label: String { "\(city) (\(abbreviation))" }
}

nonisolated enum ZoneCatalog {
    struct ZoneTabRow: Equatable, Sendable {
        let countryCode: String
        let zoneID: String
        let comment: String?
    }

    private static let day: TimeInterval = 86_400

    // MARK: Loading

    /// zone.tab's format: `CC <tab> coordinates <tab> TZ [<tab> comment]`; lines starting with # are comments.
    static func parse(_ text: String) -> [ZoneTabRow] {
        text.split(separator: "\n").compactMap { line in
            if line.hasPrefix("#") { return nil }
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 3 else { return nil }
            let comment = cols.count > 3 && !cols[3].isEmpty ? String(cols[3]) : nil
            return ZoneTabRow(countryCode: String(cols[0]), zoneID: String(cols[2]), comment: comment)
        }
    }

    static func bundledRows(bundle: Bundle = .main) -> [ZoneTabRow] {
        guard let url = bundle.url(forResource: "zone", withExtension: "tab"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return parse(text)
    }

    /// Builds the list. Run only while the popover is open; the result is thrown away on close.
    static func build(from rows: [ZoneTabRow], now: Date = Date(), locale: Locale = .current) -> [ZoneEntry] {
        let english = Locale(identifier: "en_US")
        // Extra abbreviations Foundation knows, e.g. "MSK" -> Europe/Moscow, keyed by zone.
        let knownAbbreviations = Dictionary(grouping: TimeZone.abbreviationDictionary, by: \.value)
            .mapValues { $0.map(\.key) }

        // Group each country's zones by how their clocks behave from now on, keeping zone.tab's order.
        // tzdata lists the most populous zone first, so the first of each group names the row.
        struct Group { var rows: [ZoneTabRow]; let zone: TimeZone; let signature: [Int] }
        var groupsByCountry: [String: [Group]] = [:]
        var countryOrder: [String] = []
        for row in rows {
            guard let zone = TimeZone(identifier: row.zoneID) else { continue }  // unknown to this OS
            let signature = behaviourSignature(of: zone, from: now)
            if groupsByCountry[row.countryCode] == nil { countryOrder.append(row.countryCode) }
            if let i = groupsByCountry[row.countryCode]?.firstIndex(where: { $0.signature == signature }) {
                groupsByCountry[row.countryCode]![i].rows.append(row)
            } else {
                groupsByCountry[row.countryCode, default: []].append(Group(rows: [row], zone: zone, signature: signature))
            }
        }

        var entries: [ZoneEntry] = []
        for code in countryOrder {
            let countryName = locale.localizedString(forRegionCode: code) ?? code
            let englishName = english.localizedString(forRegionCode: code) ?? code
            let multiZone = groupsByCountry[code]!.count > 1
            for group in groupsByCountry[code]! {
                var groupRows = group.rows
                if let i = groupRows.firstIndex(where: { preferredMainZones.contains($0.zoneID) }) {
                    groupRows.insert(groupRows.remove(at: i), at: 0)
                }
                let main = groupRows[0]
                let mainZone = TimeZone(identifier: main.zoneID) ?? group.zone
                let city = cityName(from: main.zoneID)
                let merged = groupRows.dropFirst().map { cityName(from: $0.zoneID) }
                let abbreviation = abbreviationLabel(for: mainZone, countryCode: code, now: now)
                let offsets = Set(group.signature.prefix(13))  // the monthly offset samples

                var tokens = Set<String>()
                for text in [countryName, englishName, city] + merged + (aliases[code] ?? []) {
                    tokens.formUnion(words(in: text))
                    tokens.insert(fold(text))  // whole phrase, so "guinea-b" or "new y" also match
                }
                if let comment = main.comment { tokens.formUnion(words(in: comment)) }
                tokens.formUnion(abbreviation.split(separator: "/").map { fold(String($0)) })
                for zoneID in groupRows.map(\.zoneID) {
                    tokens.insert(fold(zoneID))
                    tokens.formUnion((knownAbbreviations[zoneID] ?? []).map(fold))
                }
                for offset in offsets {
                    let text = offsetText(offset)
                    tokens.formUnion(["utc" + text, "gmt" + text, text])
                }
                tokens.insert(code.lowercased())

                entries.append(ZoneEntry(
                    place: Place(countryCode: code, zoneID: main.zoneID),
                    countryName: countryName,
                    city: city,
                    region: multiZone ? main.comment : nil,
                    abbreviation: abbreviation,
                    alsoCovers: merged,
                    coveredZoneIDs: groupRows.map(\.zoneID),
                    searchTokens: tokens.sorted()
                ))
            }
        }
        // Countries alphabetically in the user's language. Ties keep zone.tab's order, because
        // Swift's `sorted` doesn't promise stability.
        return entries.enumerated().sorted { a, b in
            switch a.element.countryName.localizedStandardCompare(b.element.countryName) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: a.offset < b.offset
            }
        }.map(\.element)
    }

    // MARK: Search

    /// Every query word must be the start of some token, so "new york", "los ang" and "united k" all work.
    /// Ranking:
    /// 0. the zone Foundation names as the abbreviation's home (EST -> New York, MSK -> Moscow)
    /// 1. an exact token match (e.g. "IST" on Ireland's GMT/IST, "London")
    /// 2. a country or city starting with the query
    /// 3. everything else
    static func search(_ entries: [ZoneEntry], query: String) -> [ZoneEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = fold(trimmed)
        guard !q.isEmpty else { return entries }
        let queryWords = q.split(separator: " ").map(String.init)
        let abbreviationHome = TimeZone.abbreviationDictionary[trimmed.uppercased()]

        var scored: [(rank: Int, index: Int, entry: ZoneEntry)] = []
        for (index, entry) in entries.enumerated() {
            let matches = queryWords.allSatisfy { word in entry.searchTokens.contains { $0.hasPrefix(word) } }
            guard matches else { continue }
            let rank: Int
            if let home = abbreviationHome, entry.coveredZoneIDs.contains(home) {
                rank = 0
            } else if entry.searchTokens.contains(q) {
                rank = 1
            } else if fold(entry.countryName).hasPrefix(q) || fold(entry.city).hasPrefix(q) {
                rank = 2
            } else {
                rank = 3
            }
            scored.append((rank, index, entry))
        }
        return scored.sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }.map(\.entry)
    }

    // MARK: Helpers

    /// Monthly GMT-offset samples for the next year, then the exact DST transition instants in that year.
    /// Two zones with the same signature show the same time from now on.
    static func behaviourSignature(of zone: TimeZone, from now: Date) -> [Int] {
        var signature = (0...12).map { zone.secondsFromGMT(for: now.addingTimeInterval(Double($0) * 30 * day)) }
        var cursor = now
        while let next = zone.nextDaylightSavingTimeTransition(after: cursor), next < now.addingTimeInterval(400 * day) {
            signature.append(Int(next.timeIntervalSince1970))
            cursor = next
        }
        return signature
    }

    /// Picks the most recognisable short names Foundation offers. The country's own English locale
    /// knows local names (en_IN -> "IST", en_GB -> "BST", en_AU -> "AEST"); en_US/en_GB are fallbacks.
    /// Zones that change clocks in the next year show "standard/daylight". Others show only the name
    /// in force now, which matters for a zone that stays on daylight time all year (e.g. "PDT").
    static func abbreviationLabel(for zone: TimeZone, countryCode: String, now: Date) -> String {
        let observesDST = zone.nextDaylightSavingTimeTransition(after: now)
            .map { $0 < now.addingTimeInterval(400 * day) } ?? false
        guard observesDST else { return abbreviation(for: zone, countryCode: countryCode, at: now) }
        let standard = shortName(for: zone, countryCode: countryCode, style: .shortStandard, at: now)
        let daylight = shortName(for: zone, countryCode: countryCode, style: .shortDaylightSaving, at: now)
        return standard == daylight ? standard : "\(standard)/\(daylight)"
    }

    /// The short name in force at `instant`, e.g. "BST" in summer and "GMT" in winter for London.
    static func abbreviation(for zone: TimeZone, countryCode: String, at instant: Date) -> String {
        let style: NSTimeZone.NameStyle = zone.isDaylightSavingTime(for: instant) ? .shortDaylightSaving : .shortStandard
        return shortName(for: zone, countryCode: countryCode, style: style, at: instant)
    }

    private static func shortName(for zone: TimeZone, countryCode: String, style: NSTimeZone.NameStyle, at instant: Date) -> String {
        let names = ["en_\(countryCode)", "en_US", "en_GB"].compactMap {
            zone.localizedName(for: style, locale: Locale(identifier: $0))
        }
        return names.first { !isOffsetName($0) } ?? names.first ?? "GMT" + offsetText(zone.secondsFromGMT(for: instant))
    }

    /// zone.tab lists most countries' zones most-populous first, but a few (Australia, Brazil...) go by
    /// geography. These are the best-known cities among zones that share a clock, used to name the row.
    private static let preferredMainZones: Set<String> = [
        "Australia/Sydney", "Australia/Adelaide",
        "America/Sao_Paulo", "America/Manaus", "America/Rio_Branco",
        "America/Edmonton", "Europe/Samara", "Asia/Tashkent",
    ]

    /// "GMT+5:30" or "UTC-3" style names, as opposed to real abbreviations such as "GMT" or "IST".
    static func isOffsetName(_ name: String) -> Bool {
        (name.hasPrefix("GMT") || name.hasPrefix("UTC")) && name.count > 3
    }

    /// 19800 -> "+5:30", -18000 -> "-5", 0 -> "+0".
    static func offsetText(_ seconds: Int) -> String {
        let sign = seconds < 0 ? "-" : "+"
        let minutes = abs(seconds) / 60
        return minutes % 60 == 0 ? "\(sign)\(minutes / 60)" : String(format: "%@%d:%02d", sign, minutes / 60, minutes % 60)
    }

    /// "America/Argentina/Buenos_Aires" -> "Buenos Aires".
    static func cityName(from zoneID: String) -> String {
        (zoneID.split(separator: "/").last.map(String.init) ?? zoneID).replacingOccurrences(of: "_", with: " ")
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    private static func words(in text: String) -> [String] {
        fold(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Common names people type that aren't the ISO country name.
    private static let aliases: [String: [String]] = [
        "GB": ["UK", "Britain", "England", "Scotland", "Wales"],
        "US": ["USA", "America"],
        "AE": ["UAE", "Emirates"],
        "KR": ["Korea"],
        "NL": ["Holland"],
        "CZ": ["Czech Republic"],
        "TR": ["Turkey"],
        "CI": ["Ivory Coast"],
        "MM": ["Burma"],
    ]
}
