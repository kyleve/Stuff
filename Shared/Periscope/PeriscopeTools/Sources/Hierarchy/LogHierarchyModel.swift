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
    @ObservationIgnored private var generation = 0

    private(set) var state: LoadState = .loading
    private(set) var scopes: [ScopeID: LogScope] = [:]

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

    func load() async {
        generation += 1
        let requested = generation
        do {
            let scopeList = try await store.scopes()
            let events = try await store.events(matching: LogQuery())
            guard requested == generation else { return }
            scopes = Dictionary(uniqueKeysWithValues: scopeList.map { ($0.id, $0) })
            state = .loaded(Self.buildForest(scopes: scopeList, events: events))
        } catch {
            guard requested == generation else { return }
            state = .failed(String(describing: error))
        }
    }

    /// The full `" / "`-joined path for a scope, for a drill-in title.
    func path(for id: ScopeID) -> String {
        LogScope.ancestry(of: id) { scopes[$0] }
            .map(\.name)
            .joined(separator: " / ")
    }

    /// Assemble the scope forest with counts. Roots are scopes with no parent
    /// (or whose parent isn't in the set); children sort by name.
    static func buildForest(scopes: [LogScope], events: [StoredLogEvent]) -> [ScopeNode] {
        var directCounts: [ScopeID: Int] = [:]
        for event in events {
            guard let primary = event.primaryScope else { continue }
            directCounts[primary, default: 0] += 1
        }

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
