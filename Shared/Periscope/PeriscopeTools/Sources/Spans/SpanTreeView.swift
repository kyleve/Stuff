import PeriscopeCore
import SwiftUI

/// The span tree: the store's completed (and still-open) spans paired and
/// nested by time containment — a trace-style view of what ran inside what,
/// with durations and exit chips. Each row drills into the span's `SpanBegan`
/// detail (and from there the tracer).
///
/// Distinct from ``OpenSpansView`` (live, in-flight spans read from the system):
/// this reads the durable store, so it shows finished spans too. Push it inside
/// an existing `NavigationStack` from a developer menu or the viewer.
public struct SpanTreeView: View {
    private let store: PeriscopeStore
    @State private var model: SpanTreeModel

    public init(store: PeriscopeStore) {
        self.store = store
        _model = State(initialValue: SpanTreeModel(store: store))
    }

    public var body: some View {
        content
            .navigationTitle("Span Tree")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.logRowDensity, .load(from: .standard))
            .periscopeBroadwayRoot()
            .task(id: ObjectIdentifier(store)) {
                if model.store !== store {
                    model = SpanTreeModel(store: store)
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
                    "Spans Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(reason),
                )
            case let .loaded(tree) where tree.isEmpty:
                ContentUnavailableView(
                    "No Spans",
                    systemImage: "stopwatch",
                    description: Text("No measured spans have been recorded yet."),
                )
            case let .loaded(tree):
                List {
                    OutlineGroup(tree, children: \.children) { node in
                        NavigationLink {
                            LogEventDetailView(
                                event: node.began,
                                scopePath: model.scopePath(for: node.began),
                                store: store,
                            )
                        } label: {
                            SpanTreeRow(node: node)
                        }
                    }
                }
                .listStyle(.plain)
        }
    }
}

/// One span in the tree: its name, exit chip (or "open"), duration, and start.
private struct SpanTreeRow: View {
    let node: SpanNode

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let row = stylesheet.row.comfortable
        let type = stylesheet.typography
        VStack(alignment: .leading, spacing: row.lineSpacing) {
            HStack(spacing: row.headerSpacing) {
                Text(node.name)
                    .font(type.spanName)
                Spacer()
                if let mode = node.exitMode {
                    SpanExitBadge(mode: mode)
                } else {
                    Text("open")
                        .font(type.spanDetail)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: row.headerSpacing) {
                Text(node.duration?.formatted() ?? "running")
                    .font(type.spanAge)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(node.begin, format: .dateTime.hour().minute().second())
                    .font(type.spanDetail)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, row.verticalPadding)
    }
}
