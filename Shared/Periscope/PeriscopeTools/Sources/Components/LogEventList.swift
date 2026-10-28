import PeriscopeCore
import SwiftUI

/// A plain, newest-first list of events, each a `LogEventRow` linking into
/// `LogEventDetailView`. The shared list body behind the inspector sheet and
/// the hierarchy's scope-subtree view (the paged viewer has its own
/// load-more list). `depth` indents rows to mirror scope nesting; it defaults
/// to flat.
struct LogEventList: View {
    let events: [StoredLogEvent]
    let store: PeriscopeStore
    let scopePath: (StoredLogEvent) -> String
    var depth: (StoredLogEvent) -> Int = { _ in 0 }

    var body: some View {
        List(events) { event in
            NavigationLink {
                LogEventDetailView(
                    event: event,
                    scopePath: scopePath(event),
                    store: store,
                )
            } label: {
                LogEventRow(event: event, scopePath: scopePath(event), depth: depth(event))
            }
        }
        .listStyle(.plain)
    }
}
