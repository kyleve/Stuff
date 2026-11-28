import PeriscopeCore
import SFSafeSymbols
import SwiftUI

/// The scope-tree browser: the store's `LogScope` hierarchy — the same tree
/// the `Log<Event>` API builds in code — as an expandable outline, each node
/// carrying its subtree event count and drilling into that scope's events.
///
/// Shown as the viewer's "Hierarchy" tab, and usable standalone pushed inside
/// an existing `NavigationStack`.
public struct LogHierarchyView: View {
    private let store: PeriscopeStore
    @State private var model: LogHierarchyModel

    public init(store: PeriscopeStore) {
        self.store = store
        _model = State(initialValue: LogHierarchyModel(store: store))
    }

    public var body: some View {
        ScopeHierarchyContent(model: model, store: store)
            .navigationTitle("Hierarchy")
            .navigationBarTitleDisplayMode(.inline)
            .periscopeBroadwayRoot()
            .task(id: ObjectIdentifier(store)) {
                if model.store !== store {
                    model = LogHierarchyModel(store: store)
                }
                await model.run()
            }
    }
}

private struct ScopeHierarchyContent: View {
    let model: LogHierarchyModel
    let store: PeriscopeStore

    var body: some View {
        switch model.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(reason):
                ContentUnavailableView(
                    "Hierarchy Unavailable",
                    systemSymbol: .exclamationmarkTriangle,
                    description: Text(reason),
                )
            case let .loaded(forest) where forest.isEmpty:
                ContentUnavailableView(
                    "No Scopes",
                    systemSymbol: .point3ConnectedTrianglepathDotted,
                    description: Text("No log scopes have been defined yet."),
                )
            case let .loaded(forest):
                ScopeHierarchyOutline(forest: forest, model: model, store: store)
        }
    }
}

/// One scope in the outline: its name and a subtree event count.
private struct ScopeTreeRow: View {
    let node: ScopeNode
    let store: PeriscopeStore
    let scopePath: () -> String

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        NavigationLink {
            ScopeEventsView(store: store, scopeID: node.id, scopePath: scopePath())
        } label: {
            HStack {
                Text(node.name)
                    .font(stylesheet.typography.scopeName)
                Spacer()
                Text("\(node.subtreeCount)")
                    .font(stylesheet.typography.scopeCount)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ScopeHierarchyOutline: View {
    let forest: [ScopeNode]
    let model: LogHierarchyModel
    let store: PeriscopeStore

    var body: some View {
        List {
            OutlineGroup(forest, children: \.children) { node in
                ScopeTreeRow(node: node, store: store, scopePath: { model.path(for: node.id) })
            }
        }
        .listStyle(.plain)
    }
}

#if DEBUG
    #Preview {
        PeriscopeToolsPreview { fixture in
            LogHierarchyView(store: fixture.store)
        }
    }
#endif
