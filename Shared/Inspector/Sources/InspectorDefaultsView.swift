import SFSafeSymbols
import SwiftUI

struct InspectorDefaultsView: View {
    @State private var model: InspectorDefaultsModel
    @State private var searchText = ""

    init(domain: InspectorConfiguration.DefaultsDomain) {
        _model = State(initialValue: InspectorDefaultsModel(domain: domain))
    }

    var body: some View {
        List(filteredEntries) { entry in
            InspectorDefaultLink(model: model, entry: entry)
        }
        .navigationTitle(model.domain.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search defaults")
        .overlay {
            InspectorDefaultsEmptyState(
                isEmpty: model.entries.isEmpty,
                hasMatches: !filteredEntries.isEmpty,
            )
        }
        .refreshable { model.reload() }
        .alert("UserDefaults Operation Failed", isPresented: $model.isPresentingError) {} message: {
            Text(model.errorMessage ?? "The operation failed.")
        }
    }

    private var filteredEntries: [InspectorDefaultEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.entries }
        return model.entries.filter {
            $0.key.localizedCaseInsensitiveContains(query)
                || $0.value.summary.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct InspectorDefaultLink: View {
    let model: InspectorDefaultsModel
    let entry: InspectorDefaultEntry

    var body: some View {
        NavigationLink {
            InspectorDefaultEditorView(model: model, entry: entry)
        } label: {
            VStack(alignment: .leading) {
                Text(entry.key)
                    .font(.body.monospaced())
                Text(entry.value.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct InspectorDefaultsEmptyState: View {
    let isEmpty: Bool
    let hasMatches: Bool

    var body: some View {
        if isEmpty {
            ContentUnavailableView(
                "No Defaults",
                systemSymbol: .sliderHorizontal3,
                description: Text("This persistent domain has no values."),
            )
        } else if !hasMatches {
            ContentUnavailableView.search
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack { InspectorDefaultsView(domain: InspectorPreviewData.defaultsDomain) }
    }
#endif
