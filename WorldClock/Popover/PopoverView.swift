import SwiftUI

/// Root of the popover. Swift note: a SwiftUI `View` is a struct describing UI, like a React function
/// component. `body` is its render function, and `@Bindable` lets child controls write back to the model.
struct PopoverView: View {
    /// Fixed size: the popover never resizes to fit its content, so content and window size can't
    /// set off a layout loop.
    static let size = CGSize(width: 380, height: 520)

    @Bindable var model: PopoverModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $model.tab) {
                Text("Clock").tag(PopoverModel.Tab.clock)
                Text("Converter").tag(PopoverModel.Tab.converter)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            switch model.tab {
            case .clock:
                CountryList(
                    entries: model.entries,
                    query: $model.clockQuery,
                    selected: model.menuBarPlace,
                    now: model.now,
                    onSelect: model.chooseForMenuBar
                )
            case .converter:
                ConverterView(model: model, converter: model.converter)
            }

            Divider()

            HStack {
                Text("Menu bar: \(model.menuBarPlace.flag) \(model.label(for: model.menuBarPlace))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .onExitCommand(perform: model.close)  // Esc closes the popover
    }
}
