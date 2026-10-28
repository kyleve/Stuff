import Foundation
import Observation
import PeriscopeCore

/// One node in the scope-tree browser: a `LogScope` plus the event counts
/// used to show activity and the child nodes `OutlineGroup` recurses into.
/// `children` is `nil` for a leaf so the outline shows no disclosure control.
struct ScopeNode: Identifiable, Hashable {
    let id: ScopeID
    let name: String
    /// Events whose primary scope is exactly this node.
    let directCount: Int
    /// Direct events plus every descendant's — what a drill-in surfaces.
    let subtreeCount: Int
    var children: [ScopeNode]?
}

/// Drives ``LogHierarchyView``: loads the store's scope tree and per-scope
/// event counts into a forest of ``ScopeNode``s, refreshing when the store
/// commits.
@MainActor
@Observable
final class LogHierarchyModel {
    /// One load's outcome — loading, the scope forest, or an honest failure.
    enum LoadState {
        case loading
        case loaded([ScopeNode])
        case failed(String)
    }

    /// Exposed so the hosting view can detect a store swap and rebuild.
    let store: PeriscopeStore

    private(set) var state: LoadState = .loading
    private(set) var scopes: [ScopeID: LogScope] = [:]

    /// Per-scope direct event counts, accumulated across refreshes so each
    /// commit only tallies the events appended since the last one.
    @ObservationIgnored private var directCounts: [ScopeID: Int] = [:]
    /// The highest event ``StoredLogEvent/sequence`` merged so far — the
    /// cursor the next refresh queries past. `nil` means nothing loaded yet,
    /// so the first fetch reads the whole store.
    @ObservationIgnored private var watermark: Int?

    init(store: PeriscopeStore) {
        self.store = store
    }

    /// Initial load plus live refresh — run from `.task` so leaving the
    /// screen cancels the stream. The changes stream is acquired *before*
    /// the initial load so a commit landing mid-load can't fall into the gap
    /// between loading and subscribing.
    func run() async {
        let changes = await store.changes()
        await load()
        for await _ in changes {
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    /// Fetch only the events appended since the last load (via the
    /// `afterSequence` cursor), fold them into the running counts, and
    /// rebuild the forest. Scopes are few and re-read whole; the expensive
    /// part — reading and decoding every event — is now bounded by what a
    /// single commit added rather than the whole store.
    func load() async {
        do {
            let scopeList = try await store.scopes()
            var query = LogQuery()
            query.afterSequence = watermark
            let newEvents = try await store.events(matching: query)
            merge(newEvents)
            scopes = Dictionary(uniqueKeysWithValues: scopeList.map { ($0.id, $0) })
            state = .loaded(Self.buildForest(scopes: scopeList, directCounts: directCounts))
        } catch {
            PeriscopeToolsLog.failures.error(
                "Log hierarchy could not read the store: \(error, privacy: .public)",
            )
            state = .failed(String(describing: error))
        }
    }

    /// Add the events strictly past the watermark into the running counts and
    /// advance it. Filtering here (not just in the query) keeps the merge
    /// idempotent: if a refresh ever re-runs over events already folded in —
    /// e.g. a re-`run()` after the view reappears — they're skipped rather
    /// than double-counted.
    private func merge(_ events: [StoredLogEvent]) {
        let floor = watermark ?? Int.min
        for event in events where event.sequence > floor {
            guard let primary = event.primaryScope else { continue }
            directCounts[primary, default: 0] += 1
        }
        if let highest = events.map(\.sequence).max() {
            watermark = max(watermark ?? highest, highest)
        }
    }

    /// The full `" / "`-joined path for a scope, for a drill-in title.
    func path(for id: ScopeID) -> String {
        LogScope.ancestry(of: id) { scopes[$0] }
            .map(\.name)
            .joined(separator: " / ")
    }

    /// Tally each event under its primary scope (`scopes.first`) — the direct
    /// count a scope owns before its descendants are folded in.
    static func directCounts(in events: [StoredLogEvent]) -> [ScopeID: Int] {
        var counts: [ScopeID: Int] = [:]
        for event in events {
            guard let primary = event.primaryScope else { continue }
            counts[primary, default: 0] += 1
        }
        return counts
    }

    /// Assemble the scope forest from precomputed direct counts. Roots are
    /// scopes with no parent (or whose parent isn't in the set); children
    /// sort by name.
    static func buildForest(scopes: [LogScope], directCounts: [ScopeID: Int]) -> [ScopeNode] {
        let knownIDs = Set(scopes.map(\.id))
        var childrenByParent: [ScopeID: [LogScope]] = [:]
        var roots: [LogScope] = []
        for scope in scopes {
            if let parent = scope.parentID, knownIDs.contains(parent) {
                childrenByParent[parent, default: []].append(scope)
            } else {
                roots.append(scope)
            }
        }

        func makeNode(_ scope: LogScope) -> ScopeNode {
            let childNodes = (childrenByParent[scope.id] ?? [])
                .sorted { $0.name < $1.name }
                .map(makeNode)
            let direct = directCounts[scope.id] ?? 0
            let subtree = direct + childNodes.reduce(0) { $0 + $1.subtreeCount }
            return ScopeNode(
                id: scope.id,
                name: scope.name,
                directCount: direct,
                subtreeCount: subtree,
                children: childNodes.isEmpty ? nil : childNodes,
            )
        }

        return roots
            .sorted { $0.name < $1.name }
            .map(makeNode)
    }
}
