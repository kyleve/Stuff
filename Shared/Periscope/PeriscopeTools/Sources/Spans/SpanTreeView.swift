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
    @Environment(\.logRowDensity) private var density

    var body: some View {
        let row = stylesheet.row[density]
        let type = stylesheet.typography
        VStack(alignment: .leading, spacing: row.lineSpacing) {
            HStack(spacing: row.headerSpacing) {
                Text(node.name)
                    .font(type.spanName)
                Spacer()
                status
            }
            HStack(spacing: row.headerSpacing) {
                Text(timing)
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

    /// The exit chip, or a word for a span that has no chip to show: "open"
    /// while it runs, "ended" for a closed span whose row recorded no exit.
    @ViewBuilder
    private var status: some View {
        switch node.outcome {
            case .open:
                Text("open")
                    .font(stylesheet.typography.spanDetail)
                    .foregroundStyle(.secondary)
            case let .ended(ended):
                if let mode = ended.mode {
                    SpanExitBadge(mode: mode)
                } else {
                    Text("ended")
                        .font(stylesheet.typography.spanDetail)
                        .foregroundStyle(.secondary)
                }
        }
    }

    /// How long the span took. Read off ``SpanNode/outcome`` so only a span
    /// that is genuinely still open can say "running" — a closed span with no
    /// readable duration says *that* instead.
    private var timing: String {
        switch node.outcome {
            case .open:
                "running"
            case let .ended(ended):
                switch ended.timing {
                    case let .measured(duration): duration.formatted()
                    case .unmeasured: "not measured"
                    case .undecodable: "duration unreadable"
                }
        }
    }
}
