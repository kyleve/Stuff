import Foundation
import Observation
import PeriscopeCore

/// Drives the log-view-mode event list: everything stored in the subtrees
/// of an inspected view's scopes, merged newest first — "every event
/// associated with this element".
@MainActor
@Observable
final class LogInspectorModel {
    enum LoadState {
        case loading
        case loaded([StoredLogEvent])
        case failed(String)
    }

    /// Cap on the loaded events; the modifier default is 500.
    let limit: Int

    /// Exposed so the hosting view can detect input swaps and rebuild.
    let store: PeriscopeStore
    let inspectedScopes: [ScopeID]

    private(set) var state: LoadState = .loading
    private(set) var scopes: [ScopeID: LogScope] = [:]

    init(store: PeriscopeStore, inspectedScopes: [ScopeID], limit: Int) {
        self.store = store
        self.inspectedScopes = inspectedScopes
        self.limit = limit
    }

    var events: [StoredLogEvent] {
        guard case let .loaded(events) = state else { return [] }
        return events
    }

    /// Initial load plus live refresh — run from `.task` so dismissing the
    /// sheet cancels the stream. The changes stream is acquired *before*
    /// the initial load so a commit landing mid-load can't fall into the
    /// gap between loading and subscribing.
    func run() async {
        let changes = await store.changes()
        await load()
        for await _ in changes {
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    func load() async {
        do {
            let scopeList = try await store.scopes()
            scopes = Dictionary(uniqueKeysWithValues: scopeList.map { ($0.id, $0) })

            var collected: [UUID: StoredLogEvent] = [:]
            for scope in inspectedScopes {
                var query = LogQuery()
                query.scope = .subtree(scope)
                query.limit = limit
                for event in try await store.events(matching: query) {
                    collected[event.id] = event
                }
            }
            let ordered = collected.values.sorted { lhs, rhs in
                (lhs.date, lhs.sequence) > (rhs.date, rhs.sequence)
            }
            state = .loaded(Array(ordered.prefix(limit)))
        } catch {
            state = .failed(String(describing: error))
        }
    }

    func scopePath(for event: StoredLogEvent) -> String {
        guard let primary = event.primaryScope else { return "" }
        return LogScope.ancestry(of: primary) { scopes[$0] }
            .map(\.name)
            .joined(separator: " / ")
    }

    /// The event's primary-scope depth below `root`, for indenting subtree
    /// rows to mirror the scope hierarchy. Zero when the event sits at (or,
    /// defensively, above) `root`.
    func depth(of event: StoredLogEvent, below root: ScopeID) -> Int {
        guard let primary = event.primaryScope else { return 0 }
        let eventDepth = LogScope.ancestry(of: primary) { scopes[$0] }.count
        let rootDepth = LogScope.ancestry(of: root) { scopes[$0] }.count
        return max(0, eventDepth - rootDepth)
    }
}
