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
            GraphSummaryView(graph: graph)
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
