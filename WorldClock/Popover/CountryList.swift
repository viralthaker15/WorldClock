import SwiftUI

/// Searchable list of country/zone rows. Used by the Clock tab and by the converter's "From" picker.
struct CountryList: View {
    let entries: [ZoneEntry]
    @Binding var query: String
    let selected: Place?
    let now: Date
    let onSelect: (ZoneEntry) -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        // Filtering ~300 rows against precomputed tokens takes microseconds, so it runs on every keystroke.
        let results = ZoneCatalog.search(entries, query: query)

        VStack(spacing: 0) {
            TextField("Search country, city or zone (e.g. EST)", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit { if let first = results.first { onSelect(first) } }  // Return picks the top hit
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ScrollViewReader { proxy in
                    List(results) { entry in
                        ZoneRow(entry: entry, isSelected: entry.place == selected, now: now)
                            .contentShape(Rectangle())  // make the whole row clickable, not just the text
                            .onTapGesture { onSelect(entry) }
                    }
                    .listStyle(.plain)
                    .onAppear {
                        if query.isEmpty, let selected { proxy.scrollTo(selected, anchor: .center) }
                    }
                }
            }
        }
        .onAppear { searchFocused = true }
    }
}

struct ZoneRow: View {
    let entry: ZoneEntry
    let isSelected: Bool
    let now: Date

    var body: some View {
        HStack(spacing: 10) {
            Text(entry.flag)
                .font(.title2)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.countryName)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text(entry.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            // Format to a String first: `Text(date, format:)` replaces the style's time zone with the
            // view environment's, which would show local time on every row.
            Text(verbatim: now.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: entry.place.timeZone)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Image(systemName: "checkmark")
                .foregroundStyle(.tint)
                .opacity(isSelected ? 1 : 0)
                .accessibilityHidden(!isSelected)
        }
        .padding(.vertical, 2)
        .help(tooltip)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var tooltip: String {
        var lines: [String] = [entry.place.zoneID]
        if let region = entry.region { lines.append(region) }
        if !entry.alsoCovers.isEmpty { lines.append("Same clock as: " + entry.alsoCovers.joined(separator: ", ")) }
        return lines.joined(separator: "\n")
    }
}
