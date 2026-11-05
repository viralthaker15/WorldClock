import Foundation

/// A country plus one of its IANA zones, e.g. ("US", "America/New_York"). This is what gets persisted.
/// The country is stored too, because some zones serve several countries and the flag comes from the country.
nonisolated struct Place: Hashable, Sendable {
    /// ISO 3166-1 alpha-2, e.g. "GB".
    let countryCode: String
    /// IANA identifier, e.g. "Europe/London".
    let zoneID: String

    static let london = Place(countryCode: "GB", zoneID: "Europe/London")
    static let india = Place(countryCode: "IN", zoneID: "Asia/Kolkata")

    var timeZone: TimeZone { TimeZone(identifier: zoneID) ?? .gmt }

    /// Flag emoji built from the two regional-indicator symbols matching the letters, e.g. "GB" -> 🇬🇧.
    var flag: String { Place.flag(for: countryCode) }

    static func flag(for countryCode: String) -> String {
        // Swift note: strings are sequences of Unicode scalars. 🇬🇧 is the scalars U+1F1EC U+1F1E7,
        // which are "G" and "B" shifted into the Regional Indicator block.
        var flag = ""
        for scalar in countryCode.uppercased().unicodeScalars {
            guard let indicator = Unicode.Scalar(0x1F1E6 + scalar.value - 65) else { return "🏳️" }
            flag.unicodeScalars.append(indicator)
        }
        return flag
    }

    var plist: [String: String] { ["countryCode": countryCode, "zoneID": zoneID] }

    init(countryCode: String, zoneID: String) {
        self.countryCode = countryCode
        self.zoneID = zoneID
    }

    /// Reads a stored place, rejecting anything this OS's tz database doesn't recognise.
    init?(plist: Any?) {
        guard let dict = plist as? [String: String],
              let code = dict["countryCode"], code.count == 2,
              let zone = dict["zoneID"], TimeZone(identifier: zone) != nil
        else { return nil }
        self.init(countryCode: code, zoneID: zone)
    }
}

/// Persisted settings, backed by UserDefaults (the macOS equivalent of localStorage, in
/// ~/Library/Preferences/com.viralthaker.WorldClock.plist).
final class AppSettings {
    static let shared = AppSettings(defaults: .standard)

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private enum Key {
        static let menuBarPlace = "menuBarPlace"
        static let converterTarget = "converterTarget"
    }

    /// The zone shown in the menu bar.
    var menuBarPlace: Place {
        get { Place(plist: defaults.object(forKey: Key.menuBarPlace)) ?? .london }
        set { defaults.set(newValue.plist, forKey: Key.menuBarPlace) }
    }

    /// The zone the converter converts into. Phase 1 has no UI for it, so it stays at India (IST)
    /// unless set with `defaults write`. The converter reads its target only from here, so phase 2
    /// just needs a picker that writes this.
    var converterTarget: Place {
        get { Place(plist: defaults.object(forKey: Key.converterTarget)) ?? .india }
        set { defaults.set(newValue.plist, forKey: Key.converterTarget) }
    }
}
