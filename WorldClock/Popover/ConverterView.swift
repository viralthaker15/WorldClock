import SwiftUI

struct ConverterView: View {
    let model: PopoverModel
    @Bindable var converter: ConverterModel

    var body: some View {
        if converter.pickingSource {
            sourcePicker
        } else {
            form
        }
    }

    private var sourcePicker: some View {
        VStack(spacing: 0) {
            HStack {
                Button { converter.pickingSource = false } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("Convert from").font(.headline)
                Spacer()
                Color.clear.frame(width: 50, height: 1)  // balances the Back button so the title is centred
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            CountryList(
                entries: model.entries,
                query: $converter.sourceQuery,
                selected: converter.source,
                now: model.now
            ) { entry in
                converter.source = entry.place
                converter.sourceQuery = ""
                converter.pickingSource = false
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                LabeledContent("From") {
                    Button { converter.pickingSource = true } label: {
                        HStack(spacing: 4) {
                            Text("\(converter.source.flag) \(model.label(for: converter.source))")
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.borderless)
                }
                // Floating input (see ConverterModel.input): the pickers show and edit its UTC reading.
                Group {
                    DatePicker("Date", selection: $converter.input, displayedComponents: .date)
                    DatePicker("Time", selection: $converter.input, displayedComponents: .hourAndMinute)
                }
                .environment(\.timeZone, .gmt)
                .environment(\.calendar, TimeMath.utcCalendar)

                HStack {
                    Spacer()
                    Button("Now") { converter.resetToNow(Date()) }
                }
            }

            Section {
                ConversionResultView(
                    outcome: converter.outcome,
                    input: converter.local,
                    source: converter.source,
                    sourceCity: ZoneCatalog.cityName(from: converter.source.zoneID),
                    target: converter.target,
                    targetName: model.entry(for: converter.target)?.countryName ?? converter.target.zoneID,
                    useSecondOccurrence: $converter.useSecondOccurrence
                )
            }
        }
        .formStyle(.grouped)
    }
}

struct ConversionResultView: View {
    let outcome: ConversionOutcome
    let input: LocalDateTime
    let source: Place
    let sourceCity: String
    let target: Place
    let targetName: String
    @Binding var useSecondOccurrence: Bool

    var body: some View {
        switch outcome {
        case .exact(let result):
            resultBlock(result)

        case .occursTwice(let first, let second):
            let chosen = useSecondOccurrence ? second : first
            let other = useSecondOccurrence ? first : second
            VStack(alignment: .leading, spacing: 10) {
                resultBlock(chosen)
                notice(
                    systemImage: "clock.arrow.2.circlepath",
                    tint: .blue,
                    text: "\(Display.time(input)) happens twice in \(sourceCity) on \(Display.date(input)) because the clocks go back. "
                        + "Showing the \(useSecondOccurrence ? "second" : "first") one: \(sourceName(chosen)), \(Display.utcOffset(chosen.sourceOffset))."
                )
                Button("Use the \(useSecondOccurrence ? "first" : "second") one (\(sourceName(other)), \(Display.utcOffset(other.sourceOffset)))") {
                    useSecondOccurrence.toggle()
                }
            }

        case .doesNotExist(let gap):
            notice(
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange,
                text: "\(Display.time(input)) doesn't exist in \(sourceCity) on \(Display.date(input)). "
                    + "The clocks jump forward from \(Display.time(gap.localStart)) to \(Display.time(gap.localEnd)). "
                    + "Pick a time outside that gap."
            )
        }
    }

    private func resultBlock(_ result: ConvertedTime) -> some View {
        let days = result.target.calendarDays(since: input)
        let abbreviation = ZoneCatalog.abbreviation(for: target.timeZone, countryCode: target.countryCode, at: result.instant)
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(target.flag) \(targetName) · \(abbreviation)")
                .foregroundStyle(.secondary)
            Text(Display.time(result.target))
                .font(.system(size: 34, weight: .semibold))
                .monospacedDigit()
                .textSelection(.enabled)
            if days != 0 {
                Text("\(Display.date(result.target)) (\(Display.dayShift(days)))")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sourceName(_ result: ConvertedTime) -> String {
        ZoneCatalog.abbreviation(for: source.timeZone, countryCode: source.countryCode, at: result.instant)
    }

    private func notice(systemImage: String, tint: Color, text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(tint)
        }
    }
}
