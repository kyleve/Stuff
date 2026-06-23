import SwiftData
import SwiftUI

/// A generic, read-only browser for any SwiftData store. Lists every entity with
/// its row count; tap one to drill into a scrollable table of its rows and
/// columns. Searchable by entity name.
///
/// The view expects an ambient `NavigationStack` (it pushes the per-entity table
/// with a `NavigationLink`), so drop it into a navigation context — a settings
/// screen, a tab, or a sheet that provides its own stack.
public struct SwiftDataInspectorView: View {
    @State private var model: SwiftDataInspectorModel
    @State private var searchText = ""

    @MainActor
    public init(configuration: SwiftDataInspectorConfiguration) {
        _model = State(initialValue: SwiftDataInspectorModel(configuration: configuration))
    }

    public var body: some View {
        List {
            ForEach(filteredEntities) { entity in
                NavigationLink {
                    EntityTableView(model: model, entity: entity)
                } label: {
                    EntityRow(entity: entity)
                }
            }
        }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search entities")
        .overlay { emptyState }
        .task { model.loadEntities() }
        .refreshable { model.loadEntities() }
    }

    private var filteredEntities: [InspectorEntity] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.entities }
        return model.entities.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.entities.isEmpty {
            ContentUnavailableView(
                "No Entities",
                systemImage: "tray",
                description: Text("This store has no model types."),
            )
        } else if filteredEntities.isEmpty {
            ContentUnavailableView.search(text: searchText)
        }
    }
}

/// One entity in the root list: its name and a row-count badge.
private struct EntityRow: View {
    let entity: InspectorEntity

    var body: some View {
        HStack {
            Label(entity.name, systemImage: "tablecells")
            Spacer()
            Text("\(entity.count)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
    #Preview("Populated") {
        NavigationStack {
            SwiftDataInspectorView(configuration: InspectorPreviewData.populatedConfiguration())
        }
    }

    #Preview("Empty") {
        NavigationStack {
            SwiftDataInspectorView(configuration: InspectorPreviewData.emptyConfiguration())
        }
    }
#endif
