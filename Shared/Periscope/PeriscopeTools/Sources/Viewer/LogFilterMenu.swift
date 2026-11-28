import PeriscopeCore
import SFSafeSymbols
import SwiftUI

struct LogFilterMenu: View {
    @Bindable var model: PeriscopeViewerModel
    @Binding var density: PeriscopeStylesheet.Density

    var body: some View {
        Menu {
            LogFilterPicker(
                title: "Level",
                all: "All Levels",
                choices: model.availableLevels,
                value: \.self,
                name: \.displayName,
                selection: $model.minimumLevel,
            )
            LogFilterPicker(
                title: "Event",
                all: "All Events",
                choices: model.eventNames,
                value: \.self,
                name: \.self,
                selection: $model.selectedEventName,
            )
            LogFilterPicker(
                title: "Scope",
                all: "All Scopes",
                choices: model.scopeChoices,
                value: \.id,
                name: \.path,
                selection: $model.selectedScope,
            )
            LogFilterPicker(
                title: "Session",
                all: "All Sessions",
                choices: model.sessions,
                value: \.id,
                name: \.displayLabel,
                selection: $model.selectedSessionID,
            )
            LogFilterPicker(
                title: "Span Exit",
                all: "All Events",
                choices: SpanExit.Mode.allCases,
                value: \.self,
                name: \.displayName,
                selection: $model.selectedSpanExitMode,
            )
            Divider()
            LogDensityPicker(density: $density)
        } label: {
            Label("Filter", systemSymbol: .line3HorizontalDecreaseCircle)
        }
    }
}

private struct LogFilterPicker<Choice, Value: Hashable>: View {
    let title: LocalizedStringKey
    let all: LocalizedStringKey
    let choices: [Choice]
    let value: KeyPath<Choice, Value>
    let name: KeyPath<Choice, String>
    @Binding var selection: Value?

    var body: some View {
        Picker(title, selection: $selection) {
            Text(all).tag(Value?.none)
            ForEach(choices, id: value) { choice in
                Text(choice[keyPath: name]).tag(Value?.some(choice[keyPath: value]))
            }
        }
    }
}

private struct LogDensityPicker: View {
    @Binding var density: PeriscopeStylesheet.Density

    var body: some View {
        Picker("Row Density", selection: $density) {
            ForEach(PeriscopeStylesheet.Density.allCases, id: \.self) { density in
                Text(density.displayName).tag(density)
            }
        }
    }
}

#if DEBUG
    #Preview {
        PeriscopeToolsPreview { fixture in
            PeriscopeViewer(store: fixture.store)
        }
    }
#endif
