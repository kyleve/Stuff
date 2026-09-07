import SFSafeSymbols
import SwiftData
import SwiftUI

/// A generic browser and destructive editor for any SwiftData store. Lists every
/// entity with its row count; tap one to drill into a scrollable table of its
/// rows and columns. Searchable by entity name.
///
/// The view expects an ambient `NavigationStack` (it pushes the per-entity table
/// with a `NavigationLink`), so drop it into a navigation context — a settings
/// screen, a tab, or a sheet that provides its own stack.
///
/// Navigation is deliberately *not* value-based (`NavigationLink(value:)` +
/// `navigationDestination(for:)`). Consumers push this view into their own stack
/// with a closure `NavigationLink { InspectorSwiftDataView(...) }`, and mixing a
/// value-based link into that same stack makes SwiftUI double-push (a tap also
/// re-fires the consumer's link). So every push here uses a closure
/// `NavigationLink`/`navigationDestination(item:)`, which composes with any host.
public struct InspectorSwiftDataView: View {
    @State private var model: InspectorSwiftDataModel
    @State private var searchText = ""
    @State private var isConfirmingStoreErase = false

    @MainActor
    public init(configuration: InspectorSwiftDataConfiguration) {
        _model = State(initialValue: InspectorSwiftDataModel(configuration: configuration))
    }

    init(model: InspectorSwiftDataModel) {
        _model = State(initialValue: model)
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
        .task { await model.loadEntities() }
        .refreshable { await model.loadEntities() }
        .toolbar {
            if model.canEraseStore {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        "Erase Store",
                        systemSymbol: .externaldriveBadgeXmark,
                        role: .destructive,
                    ) {
                        isConfirmingStoreErase = true
                    }
                    .confirmationDialog(
                        "Erase the complete SwiftData store?",
                        isPresented: $isConfirmingStoreErase,
                        titleVisibility: .visible,
                    ) {
                        Button("Erase Store", role: .destructive) {
                            Task { _ = await model.eraseStore() }
                        }
                    } message: {
                        Text("Every entity and row will be removed. This cannot be undone.")
                    }
                }
            }
        }
        .alert(
            "SwiftData Operation Failed",
            isPresented: $model.isPresentingOperationError,
        ) {} message: {
            Text(model.operationError ?? "The operation failed.")
        }
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
                systemSymbol: .tray,
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
            Label(entity.name, systemSymbol: .tablecells)
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
            InspectorSwiftDataView(configuration: InspectorPreviewData.populatedConfiguration())
        }
    }

    #Preview("Empty") {
        NavigationStack {
            InspectorSwiftDataView(configuration: InspectorPreviewData.emptyConfiguration())
        }
    }
#endif
