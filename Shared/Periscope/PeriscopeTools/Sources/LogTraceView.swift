import PeriscopeCore
import SwiftUI

/// The log tracer: starting from one event (typically an error), shows the
/// events that led up to it — back through time, across its linked scopes,
/// and up the scope tree — so an error can be followed to its origin.
/// Tapping a trail event opens its detail, from which tracing can continue
/// further back.
///
/// Designed to be pushed inside an existing `NavigationStack`.
public struct LogTraceView: View {
    private let store: PeriscopeStore
    @State private var model: LogTraceModel

    public init(store: PeriscopeStore, origin: StoredLogEvent) {
        self.store = store
        _model = State(initialValue: LogTraceModel(store: store, origin: origin))
    }

    public var body: some View {
        List {
            Section("Origin") {
                LogEventRow(
                    event: model.origin,
                    scopePath: model.scopePath(for: model.origin),
                )
            }
            Section("Leading up to it") {
                content
            }
        }
        .listStyle(.plain)
        .navigationTitle("Trace")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
            case .loading:
                ProgressView()
            case let .failed(reason):
                Label(reason, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            case let .loaded(trail) where trail.isEmpty:
                Text("No earlier events in this event's scopes.")
                    .foregroundStyle(.secondary)
            case let .loaded(trail):
                ForEach(trail) { event in
                    NavigationLink {
                        LogEventDetailView(
                            event: event,
                            scopePath: model.scopePath(for: event),
                            store: store,
                        )
                    } label: {
                        LogEventRow(event: event, scopePath: model.scopePath(for: event))
                    }
                }
        }
    }
}
