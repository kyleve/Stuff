import PeriscopeCore
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
        content
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

    @ViewBuilder
    private var content: some View {
        switch model.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(reason):
                ContentUnavailableView(
                    "Hierarchy Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(reason),
                )
            case let .loaded(forest) where forest.isEmpty:
                ContentUnavailableView(
                    "No Scopes",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("No log scopes have been defined yet."),
                )
            case let .loaded(forest):
                List {
                    OutlineGroup(forest, children: \.children) { node in
                        NavigationLink {
                            ScopeEventsView(
                                store: store,
                                scopeID: node.id,
                                scopePath: model.path(for: node.id),
                            )
                        } label: {
                            ScopeTreeRow(node: node)
                        }
                    }
                }
                .listStyle(.plain)
        }
    }
}

/// One scope in the outline: its name and a subtree event count.
private struct ScopeTreeRow: View {
    let node: ScopeNode

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
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
