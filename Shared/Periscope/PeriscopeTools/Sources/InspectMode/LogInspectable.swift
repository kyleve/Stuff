import PeriscopeCore
import SFSafeSymbols
import SwiftUI

extension View {
    /// Mark this view inspectable in "log view mode": when the environment
    /// ``PeriscopeInspector`` is enabled, the view gains a badge that opens
    /// the newest `limit` stored events in the given context's scope
    /// subtrees — e.g. wrap a payment row and see everything associated
    /// with that payment. With no inspector or the mode off, the view
    /// renders unchanged.
    public func logInspectable(_ log: Log<some LogScopeDefinition>, limit: Int = 500) -> some View {
        modifier(LogInspectableModifier(scopes: log.scopes.map(\.id), limit: limit))
    }

    /// Inspectability keyed to a `LogContextProviding` model's instance
    /// context — `.logInspectable(payment)`.
    public func logInspectable(
        _ provider: some LogContextProviding,
        limit: Int = 500,
    ) -> some View {
        logInspectable(provider.log, limit: limit)
    }
}

struct LogInspectableModifier: ViewModifier {
    let scopes: [ScopeID]
    let limit: Int

    @Environment(\.periscopeInspector) private var inspector
    @Environment(\.stylesheet) private var stylesheet
    @State private var isPresentingEvents = false

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if let inspector, inspector.isEnabled {
                Button("Inspect Logs", systemSymbol: .waveformBadgeMagnifyingglass) {
                    isPresentingEvents = true
                }
                .labelStyle(.iconOnly)
                .font(.caption)
                .padding(stylesheet.badge.inspectPadding)
                .background(stylesheet.palette.inspectBadge.opacity(0.85), in: .circle)
                .foregroundStyle(.white)
                .padding(2)
                .sheet(isPresented: $isPresentingEvents) {
                    NavigationStack {
                        LogInspectorView(store: inspector.store, scopes: scopes, limit: limit)
                    }
                }
            }
        }
    }
}

/// The sheet log view mode presents: the inspected context's events, newest
/// first, each linking into the standard event detail (and from there the
/// tracer).
struct LogInspectorView: View {
    let store: PeriscopeStore
    let scopes: [ScopeID]
    let limit: Int

    @State private var model: LogInspectorModel
    @Environment(\.dismiss) private var dismiss

    init(store: PeriscopeStore, scopes: [ScopeID], limit: Int) {
        self.store = store
        self.scopes = scopes
        self.limit = limit
        _model = State(initialValue: LogInspectorModel(
            store: store,
            inspectedScopes: scopes,
            limit: limit,
        ))
    }

    /// The identity of this view's inputs — re-keying the task rebinds the
    /// model when any changes in place.
    private struct Inputs: Equatable {
        let store: ObjectIdentifier
        let scopes: [ScopeID]
        let limit: Int
    }

    var body: some View {
        content
            .navigationTitle("Element Logs")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.logRowDensity, .load(from: .standard))
            .periscopeBroadwayRoot()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: Inputs(store: ObjectIdentifier(store), scopes: scopes, limit: limit)) {
                if model.store !== store || model.inspectedScopes != scopes
                    || model.limit != limit
                {
                    model = LogInspectorModel(
                        store: store,
                        inspectedScopes: scopes,
                        limit: limit,
                    )
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
                    "Logs Unavailable",
                    systemSymbol: .exclamationmarkTriangle,
                    description: Text(reason),
                )
            case let .loaded(events) where events.isEmpty:
                ContentUnavailableView(
                    "No Events",
                    systemSymbol: .docTextMagnifyingglass,
                    description: Text("Nothing has been logged in this element's scopes."),
                )
            case let .loaded(events):
                LogEventList(
                    events: events,
                    store: store,
                    scopePath: model.scopePath(for:),
                )
        }
    }
}
