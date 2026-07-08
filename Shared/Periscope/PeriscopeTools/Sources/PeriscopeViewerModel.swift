import Foundation
import Observation
import PeriscopeCore

/// Drives ``PeriscopeViewer``: pages `PeriscopeStore` queries into
/// observable state, re-querying when filters change or the store commits
/// new events.
@MainActor
@Observable
final class PeriscopeViewerModel {
    /// One load's outcome — loading, a page stack, or an honest failure.
    enum LoadState {
        case loading
        case loaded([StoredLogEvent])
        case failed(String)
    }

    /// A scope option in the filter menu, labeled by its full path.
    struct ScopeChoice: Identifiable, Hashable {
        let id: ScopeID
        let path: String
    }

    static let pageSize = 200

    private let store: PeriscopeStore
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    private(set) var state: LoadState = .loading
    private(set) var scopes: [ScopeID: LogScope] = [:]
    private(set) var sessions: [LogSession] = []
    private(set) var canLoadMore = false

    var searchText = "" {
        didSet { if searchText != oldValue { scheduleReload() } }
    }

    /// `nil` shows every level.
    var minimumLevel: LogLevel? {
        didSet { if minimumLevel != oldValue { scheduleReload() } }
    }

    /// `nil` shows every event type.
    var selectedEventName: String? {
        didSet { if selectedEventName != oldValue { scheduleReload() } }
    }

    /// `nil` shows every session.
    var selectedSessionID: UUID? {
        didSet { if selectedSessionID != oldValue { scheduleReload() } }
    }

    /// `nil` shows every scope; set filters to that scope's subtree.
    var selectedScope: ScopeID? {
        didSet { if selectedScope != oldValue { scheduleReload() } }
    }

    init(store: PeriscopeStore) {
        self.store = store
    }

    /// The loaded page stack (empty while loading or failed).
    var events: [StoredLogEvent] {
        guard case let .loaded(events) = state else { return [] }
        return events
    }

    /// Distinct event names among loaded events, for the type filter.
    var eventNames: [String] {
        Array(Set(events.map(\.eventName))).sorted()
    }

    /// The standard ladder plus any custom levels present in loaded events.
    var availableLevels: [LogLevel] {
        Array(Set(LogLevel.standardLevels + events.map(\.level))).sorted()
    }

    /// Every known scope, labeled by full path, for the scope filter.
    var scopeChoices: [ScopeChoice] {
        scopes.keys
            .map { ScopeChoice(id: $0, path: path(for: $0)) }
            .sorted { $0.path < $1.path }
    }

    /// Initial load plus live refresh — run from `.task` so leaving the
    /// screen cancels the stream. The changes stream is acquired *before*
    /// the initial load: a commit landing mid-load buffers in the stream
    /// and triggers a refresh, instead of falling into the gap between
    /// loading and subscribing.
    func run() async {
        let changes = await store.changes()
        await load()
        for await _ in changes {
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    /// Query the first page for the active filters, plus the scope and
    /// session catalogs the filter menus need.
    func load() async {
        generation += 1
        let requested = generation
        do {
            var query = activeQuery
            query.limit = Self.pageSize
            let page = try await store.events(matching: query)
            let scopeList = try await store.scopes()
            let sessionList = try await store.sessions()
            guard requested == generation else { return }
            state = .loaded(page)
            scopes = Dictionary(uniqueKeysWithValues: scopeList.map { ($0.id, $0) })
            sessions = sessionList
            canLoadMore = page.count == Self.pageSize
        } catch {
            guard requested == generation else { return }
            state = .failed(String(describing: error))
        }
    }

    /// Fetch and append the next page.
    func loadMore() async {
        guard case let .loaded(current) = state, canLoadMore else { return }
        let requested = generation
        do {
            var query = activeQuery
            query.limit = Self.pageSize
            query.offset = current.count
            let next = try await store.events(matching: query)
            guard requested == generation else { return }
            state = .loaded(current + next)
            canLoadMore = next.count == Self.pageSize
        } catch {
            guard requested == generation else { return }
            state = .failed(String(describing: error))
        }
    }

    /// Every event matching the active filters (unpaged), as NDJSON.
    func exportNDJSON() async throws -> String {
        let all = try await store.events(matching: activeQuery)
        return NDJSONExporter.export(events: all, scopes: scopes)
    }

    /// The primary scope's path for a row's caption.
    func scopePath(for event: StoredLogEvent) -> String {
        guard let primary = event.primaryScope else { return "" }
        return path(for: primary)
    }

    private func path(for scope: ScopeID) -> String {
        var names: [String] = []
        var next: ScopeID? = scope
        while let id = next, let resolved = scopes[id] {
            names.append(resolved.name)
            next = resolved.parentID
        }
        return names.reversed().joined(separator: " / ")
    }

    private var activeQuery: LogQuery {
        var query = LogQuery()
        query.minimumLevel = minimumLevel
        query.eventName = selectedEventName
        query.sessionID = selectedSessionID
        query.scope = selectedScope.map(ScopeFilter.subtree)
        query.messageContains = searchText.isEmpty ? nil : searchText
        return query
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            await self?.load()
        }
    }
}
