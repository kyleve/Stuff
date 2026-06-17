import CodeGraphModel
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(GraphStore.self) private var store
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(store.sourceURL?.lastPathComponent ?? "CodeGraph")
                .toolbar { toolbar }
                .fileImporter(
                    isPresented: $isImporting,
                    allowedContentTypes: [.json],
                ) { result in
                    if case let .success(url) = result {
                        store.open(url)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let graph = store.graph {
            GraphContainer(graph: graph)
                .id(graph.generatedAt)
        } else {
            EmptyStateView(error: store.loadError) { isImporting = true }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                isImporting = true
            } label: {
                Label("Open graph.json", systemImage: "folder")
            }
        }
        if store.graph != nil {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.reload()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}

/// Owns the per-graph view model and hosts the canvas + inspector. Keyed by the
/// graph's timestamp so a hot reload rebuilds it from the new snapshot.
private struct GraphContainer: View {
    @State private var model: GraphViewModel
    @State private var showingFilters = false

    init(graph: CodeGraph) {
        _model = State(initialValue: GraphViewModel(graph: graph))
    }

    var body: some View {
        @Bindable var model = model
        GraphCanvasView(model: model)
            .inspector(isPresented: $model.isInspectorPresented) {
                InspectorView(model: model, nodeID: model.selection ?? "")
                    .inspectorColumnWidth(min: 250, ideal: 310, max: 440)
            }
            .toolbar { toolbar }
            .popover(isPresented: $showingFilters) {
                FilterPanel(model: model)
            }
            .task { model.relayout() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.isFocused {
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    model.clearFocus()
                } label: {
                    Label("Clear focus", systemImage: "scope")
                }
            }
        }
        if !model.pinned.isEmpty {
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    model.unpinAll()
                } label: {
                    Label("Unpin all", systemImage: "pin.slash")
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showingFilters = true
            } label: {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }
}
