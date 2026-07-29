import PeriscopeCore
import SwiftUI

/// Span history: the store's closed spans grouped by kind (`SpanEnded.name`),
/// each row showing the recorded instance count and the p50/p90/p95/p99 of
/// their durations. Tapping a kind drills into every closed span of that kind,
/// newest first, each linking to its detail (and the tracer).
///
/// Distinct from ``SpanTreeView`` (begin/end pairs nested into a trace tree):
/// this aggregates ends by kind for a timing overview. Push it inside an
/// existing `NavigationStack` from a developer menu or the viewer.
public struct SpanHistoryView: View {
    private let store: PeriscopeStore
    @State private var model: SpanHistoryModel

    public init(store: PeriscopeStore) {
        self.store = store
        _model = State(initialValue: SpanHistoryModel(store: store))
    }

    public var body: some View {
        content
            .navigationTitle("Span History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.availableScopes.count > 1 {
                    ToolbarItem(placement: .primaryAction) {
                        scopeMenu
                    }
                }
            }
            .environment(\.logRowDensity, .load(from: .standard))
            .periscopeBroadwayRoot()
            .task(id: ObjectIdentifier(store)) {
                if model.store !== store {
                    model = SpanHistoryModel(store: store)
                }
                await model.run()
            }
    }

    /// Which builds the percentiles pool. Only shown when the store's sessions
    /// can support more than one scope — a store with a single unidentified
    /// session has nothing to narrow to.
    private var scopeMenu: some View {
        Menu {
            Picker("Builds", selection: $model.scope) {
                ForEach(model.availableScopes, id: \.self) { scope in
                    Text(scope.displayName).tag(scope)
                }
            }
        } label: {
            Label("Builds", systemImage: "line.3.horizontal.decrease.circle")
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
            case let .loaded(summaries) where summaries.isEmpty:
                ContentUnavailableView(
                    "No Spans",
                    systemImage: "stopwatch",
                    // A narrowed scope with nothing in it is a different fact
                    // from an empty store, and the reader needs to know which.
                    description: Text(model.emptyStateDescription),
                )
            case let .loaded(summaries):
                List {
                    Section {
                        ForEach(summaries) { summary in
                            NavigationLink {
                                SpanKindDetailView(
                                    summary: summary,
                                    scopePath: model.scopePath(for:),
                                    store: store,
                                )
                            } label: {
                                SpanKindRow(summary: summary)
                            }
                        }
                    } header: {
                        Text(model.scopeSummary)
                    }
                }
                .listStyle(.plain)
        }
    }
}

/// One span kind: its name and a stat strip — instance count plus the duration
/// percentiles (or a note when no instance recorded a duration).
private struct SpanKindRow: View {
    let summary: SpanKindSummary

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.logRowDensity) private var density

    var body: some View {
        let row = stylesheet.row[density]
        let type = stylesheet.typography
        VStack(alignment: .leading, spacing: row.lineSpacing) {
            HStack(spacing: row.headerSpacing) {
                Text(summary.kind.text)
                    .font(type.spanName)
                if summary.kind.isRecovered {
                    // The payload didn't decode, so this bucket's name came
                    // from the row's message — say so rather than let it read
                    // as a span kind the code actually declares.
                    Text("unreadable payload")
                        .font(type.spanDetail)
                        .foregroundStyle(.tertiary)
                }
            }
            HStack(alignment: .top, spacing: row.headerSpacing) {
                SpanStatCell(label: "runs", value: "\(summary.count)")
                if let percentiles = summary.percentiles {
                    SpanStatCell(label: "p50", value: percentiles.p50.formatted())
                    SpanStatCell(label: "p90", value: percentiles.p90.formatted())
                    SpanStatCell(label: "p95", value: percentiles.p95.formatted())
                    SpanStatCell(label: "p99", value: percentiles.p99.formatted())
                } else {
                    Text("no measured durations")
                        .font(type.spanDetail)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
        }
        .padding(.vertical, row.verticalPadding)
    }
}

/// A labelled statistic in the kind row's strip — a caption over a monospaced
/// value, sharing the row's width evenly with its siblings.
private struct SpanStatCell: View {
    let label: String
    let value: String

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let type = stylesheet.typography
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(type.spanDetail)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(type.spanAge)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Every closed span of one kind, newest first, over the shared event list —
/// each row links into the span's detail and the tracer.
private struct SpanKindDetailView: View {
    let summary: SpanKindSummary
    let scopePath: (StoredLogEvent) -> String
    let store: PeriscopeStore

    var body: some View {
        LogEventList(events: summary.events, store: store, scopePath: scopePath)
            .navigationTitle(summary.kind.text)
            .navigationBarTitleDisplayMode(.inline)
    }
}
