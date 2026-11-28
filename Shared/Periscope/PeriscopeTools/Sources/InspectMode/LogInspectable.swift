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
    @State private var isPresentingEvents = false

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if let inspector, inspector.isEnabled {
                InspectLogsButton(
                    store: inspector.store,
                    scopes: scopes,
                    limit: limit,
                    isPresentingEvents: $isPresentingEvents,
                )
            }
        }
    }
}

private struct InspectLogsButton: View {
    let store: PeriscopeStore
    let scopes: [ScopeID]
    let limit: Int
    @Binding var isPresentingEvents: Bool
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
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
                LogInspectorView(store: store, scopes: scopes, limit: limit)
            }
        }
    }
}

#if DEBUG
    #Preview {
        @Previewable @State var isPresentingEvents = false
        PeriscopeToolsPreview { fixture in
            InspectLogsButton(
                store: fixture.store,
                scopes: [fixture.scope.id],
                limit: 100,
                isPresentingEvents: $isPresentingEvents,
            )
        }
    }
#endif
