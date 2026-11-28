import PeriscopeCore
import SFSafeSymbols
import SwiftUI

struct LogEventLink: View {
    let event: StoredLogEvent
    let scopePath: String
    let store: PeriscopeStore
    var depth = 0

    var body: some View {
        NavigationLink {
            LogEventDetailView(
                event: event,
                scopePath: scopePath,
                store: store,
            )
        } label: {
            LogEventRow(event: event, scopePath: scopePath, depth: depth)
        }
    }
}

#if DEBUG
    #Preview {
        PeriscopeToolsPreview { fixture in
            PeriscopeViewer(store: fixture.store)
        }
    }
#endif
