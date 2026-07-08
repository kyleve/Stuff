import Foundation
import Observation
import PeriscopeCore

/// Drives ``LogTraceView``: from an origin event, collects the events that
/// led up to it — everything earlier in the subtrees of the origin's scopes
/// (all of them, so linked model + UI contexts both trace), everything
/// logged directly at their ancestor scopes on the way up the tree, and the
/// origin's span pair — merged newest first.
@MainActor
@Observable
final class LogTraceModel {
    enum LoadState {
        case loading
        case loaded([StoredLogEvent])
        case failed(String)
    }

    /// Cap on the assembled trail (and on each underlying query).
    static let limit = 100

    let origin: StoredLogEvent
    /// Exposed so the hosting view can detect a store swap and rebuild.
    let store: PeriscopeStore

    private(set) var state: LoadState = .loading
    private(set) var scopes: [ScopeID: LogScope] = [:]

    init(store: PeriscopeStore, origin: StoredLogEvent) {
        self.store = store
        self.origin = origin
    }

    /// The trail leading up to the origin (origin itself excluded), newest
    /// first.
    var trail: [StoredLogEvent] {
        guard case let .loaded(events) = state else { return [] }
        return events
    }

    func load() async {
        do {
            let scopeList = try await store.scopes()
            scopes = Dictionary(uniqueKeysWithValues: scopeList.map { ($0.id, $0) })

            var collected: [UUID: StoredLogEvent] = [:]
            if let span = origin.spanID {
                for event in try await store.events(inSpan: span) {
                    collected[event.id] = event
                }
            }
            for filter in traceFilters() {
                var query = LogQuery()
                query.end = origin.date
                query.scope = filter
                query.limit = Self.limit
                for event in try await store.events(matching: query) {
                    collected[event.id] = event
                }
            }

            // "Leading up to it" means strictly before: the date-bounded
            // queries are inclusive, so same-millisecond events that landed
            // *after* the origin (higher insertion sequence) — and the
            // origin itself — are trimmed here, where the ordering key
            // already lives.
            let ordered = collected.values
                .filter { ($0.date, $0.sequence) < (origin.date, origin.sequence) }
                .sorted { lhs, rhs in
                    (lhs.date, lhs.sequence) > (rhs.date, rhs.sequence)
                }
            state = .loaded(Array(ordered.prefix(Self.limit)))
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

    /// Subtree filters for each of the origin's scopes (events within the
    /// same contexts), plus exact filters for every ancestor on the way to
    /// each root (the enclosing layers' own events) — but not siblings.
    private func traceFilters() -> [ScopeFilter] {
        var filters = origin.scopes.map(ScopeFilter.subtree)
        for scope in origin.scopes {
            var next = scopes[scope]?.parentID
            while let id = next {
                filters.append(.exactly(id))
                next = scopes[id]?.parentID
            }
        }
        return filters
    }
}
