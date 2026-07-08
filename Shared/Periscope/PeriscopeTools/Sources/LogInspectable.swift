import PeriscopeCore
import SwiftUI

extension View {
    /// Mark this view inspectable in "log view mode": when the environment
    /// ``PeriscopeInspector`` is enabled, the view gains a badge that opens
    /// every stored event in the given context's scope subtrees — e.g. wrap
    /// a payment row and see everything associated with that payment. With
    /// no inspector or the mode off, the view renders unchanged.
    public func logInspectable(_ log: Log<some LogEvent>) -> some View {
        modifier(LogInspectableModifier(scopes: log.scopes.map(\.id)))
    }

    /// Inspectability keyed to a `LogContextProviding` model's instance
    /// context — `.logInspectable(payment)`.
    public func logInspectable(_ provider: some LogContextProviding) -> some View {
        logInspectable(provider.log)
    }
}

struct LogInspectableModifier: ViewModifier {
    let scopes: [ScopeID]

    @Environment(\.periscopeInspector) private var inspector
    @State private var isPresentingEvents = false

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if let inspector, inspector.isEnabled {
                Button("Inspect Logs", systemImage: "waveform.badge.magnifyingglass") {
                    isPresentingEvents = true
                }
                .labelStyle(.iconOnly)
                .font(.caption)
                .padding(4)
                .background(.purple.opacity(0.85), in: .circle)
                .foregroundStyle(.white)
                .padding(2)
                .sheet(isPresented: $isPresentingEvents) {
                    NavigationStack {
                        LogInspectorView(store: inspector.store, scopes: scopes)
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

    @State private var model: LogInspectorModel
    @Environment(\.dismiss) private var dismiss

    init(store: PeriscopeStore, scopes: [ScopeID]) {
        self.store = store
        self.scopes = scopes
        _model = State(initialValue: LogInspectorModel(store: store, inspectedScopes: scopes))
    }

    var body: some View {
        content
            .navigationTitle("Element Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
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
                    systemImage: "exclamationmark.triangle",
                    description: Text(reason),
                )
            case let .loaded(events) where events.isEmpty:
                ContentUnavailableView(
                    "No Events",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Nothing has been logged in this element's scopes."),
                )
            case let .loaded(events):
                List(events) { event in
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
                .listStyle(.plain)
        }
    }
}
