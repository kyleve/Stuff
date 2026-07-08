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
    private let origin: StoredLogEvent
    @State private var model: LogTraceModel

    public init(store: PeriscopeStore, origin: StoredLogEvent) {
        self.store = store
        self.origin = origin
        _model = State(initialValue: LogTraceModel(store: store, origin: origin))
    }

    /// The identity of this view's inputs — re-keying the task rebinds the
    /// model when either changes in place.
    private struct Inputs: Equatable {
        let store: ObjectIdentifier
        let origin: UUID
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
        .task(id: Inputs(store: ObjectIdentifier(store), origin: origin.id)) {
            if model.store !== store || model.origin.id != origin.id {
                model = LogTraceModel(store: store, origin: origin)
            }
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
