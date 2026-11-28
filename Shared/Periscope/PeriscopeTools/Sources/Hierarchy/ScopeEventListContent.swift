import PeriscopeCore
import SFSafeSymbols
import SwiftUI

struct ScopeEventListContent: View {
    let model: LogInspectorModel
    let store: PeriscopeStore
    let emptyDescription: String
    var depth: (StoredLogEvent) -> Int = { _ in 0 }

    var body: some View {
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
                    description: Text(emptyDescription),
                )
            case let .loaded(events):
                LogEventList(
                    events: events,
                    store: store,
                    scopePath: model.scopePath(for:),
                    depth: depth,
                )
        }
    }
}

#if DEBUG
    #Preview {
        PeriscopeToolsPreview { fixture in
            ScopeEventsView(
                store: fixture.store,
                scopeID: fixture.scope.id,
                scopePath: fixture.scope.name,
            )
        }
    }
#endif
