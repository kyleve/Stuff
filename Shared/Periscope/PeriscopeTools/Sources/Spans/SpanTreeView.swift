import PeriscopeCore
import SFSafeSymbols
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
        SpanTreeContent(model: model, store: store)
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
}

private struct SpanTreeContent: View {
    let model: SpanTreeModel
    let store: PeriscopeStore

    var body: some View {
        switch model.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(reason):
                ContentUnavailableView(
                    "Spans Unavailable",
                    systemSymbol: .exclamationmarkTriangle,
                    description: Text(reason),
                )
            case let .loaded(tree) where tree.isEmpty:
                ContentUnavailableView(
                    "No Spans",
                    systemSymbol: .stopwatch,
                    description: Text("No measured spans have been recorded yet."),
                )
            case let .loaded(tree):
                SpanTreeOutline(tree: tree, model: model, store: store)
        }
    }
}

private struct SpanTreeRow: View {
    let node: SpanNode
    let scopePath: () -> String
    let store: PeriscopeStore
    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.logRowDensity) private var density

    var body: some View {
        let row = stylesheet.row[density]
        NavigationLink {
            LogEventDetailView(event: node.began, scopePath: scopePath(), store: store)
        } label: {
            VStack(alignment: .leading, spacing: row.lineSpacing) {
                SpanTreeHeader(node: node)
                SpanTreeTiming(node: node)
            }
            .padding(.vertical, row.verticalPadding)
        }
    }
}

private struct SpanTreeHeader: View {
    let node: SpanNode
    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.logRowDensity) private var density

    var body: some View {
        HStack(spacing: stylesheet.row[density].headerSpacing) {
            Text(node.name)
                .font(stylesheet.typography.spanName)
            Spacer()
            SpanOutcomeLabel(node: node)
        }
    }
}

private struct SpanTreeTiming: View {
    let node: SpanNode
    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.logRowDensity) private var density

    var body: some View {
        HStack(spacing: stylesheet.row[density].headerSpacing) {
            Text(timing)
                .font(stylesheet.typography.spanAge)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(node.begin, format: .dateTime.hour().minute().second())
                .font(stylesheet.typography.spanDetail)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
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

private struct SpanOutcomeLabel: View {
    let node: SpanNode
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
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
}

private struct SpanTreeOutline: View {
    let tree: [SpanNode]
    let model: SpanTreeModel
    let store: PeriscopeStore

    var body: some View {
        List {
            OutlineGroup(tree, children: \.children) { node in
                SpanTreeRow(
                    node: node,
                    scopePath: { model.scopePath(for: node.began) },
                    store: store,
                )
            }
        }
        .listStyle(.plain)
    }
}

#if DEBUG
    #Preview {
        PeriscopeToolsPreview { fixture in
            SpanTreeView(store: fixture.store)
        }
    }
#endif
