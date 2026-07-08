import Foundation
import os
import SwiftData

/// The SwiftData-backed log store: the durable `LogSink`.
///
/// One store holds every logging system's events in one database — events
/// keep their full scope hierarchy (many-to-many), their session (per-launch
/// resource metadata), and their JSON payload, so weeks of history stay
/// queryable by time, level, event type, scope subtree, and session.
///
/// The store is a `@ModelActor`: all reads and writes run on its executor
/// against `modelContext`, and every delivered batch commits in one save —
/// `flush()` has nothing left to do. Sink failures can't propagate (the
/// pipeline is fire-and-forget), so persistence errors log to OSLog and
/// count in ``writeFailureCount`` rather than vanishing.
///
/// Wire it in at startup:
///
/// ```swift
/// let store = try await PeriscopeStore.make(
///     storage: .onDisk,
///     session: .current(),
/// )
/// Periscope.shared.add(sink: store)
/// ```
@ModelActor
public actor PeriscopeStore: LogSink {
    /// Backing storage. `onDisk` persists to `Periscope.store` in the app's
    /// default SwiftData location; `inMemory` is for tests and previews.
    public enum Storage: Sendable {
        case inMemory
        case onDisk
    }

    /// Internal-failure telemetry: logging must never crash or throw into
    /// the pipeline, so persistence problems land here and in OSLog.
    private static let failureLogger = os.Logger(
        subsystem: "com.stuff.periscope",
        category: "PeriscopeStore",
    )

    private var activeSessionRow: SDLogSession?
    private var scopeRowCache: [UUID: SDLogScope] = [:]
    private var tagRowCache: [LogTag: SDLogTag] = [:]
    private var changeObservers: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var writeFailures = 0
    private var nextSequence: Int?

    public static func makeContainer(storage: Storage) throws -> ModelContainer {
        let schema = Schema(PeriscopeSchema.models)
        let configuration = ModelConfiguration(
            "Periscope",
            schema: schema,
            isStoredInMemoryOnly: storage == .inMemory,
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// App-wiring factory: opens the store and starts `session` so every
    /// subsequent event is attributed to this launch.
    public static func make(storage: Storage, session: LogSession) async throws -> PeriscopeStore {
        let container = try makeContainer(storage: storage)
        let store = PeriscopeStore(modelContainer: container)
        try await store.startSession(session)
        return store
    }

    /// Test/preview factory: a fresh in-memory store per call.
    @_spi(Testing) public static func inMemory(
        session: LogSession,
    ) async throws -> PeriscopeStore {
        try await make(storage: .inMemory, session: session)
    }

    // MARK: Sessions

    /// Record `session` as this launch's resource metadata; every event
    /// written afterwards references it.
    public func startSession(_ session: LogSession) throws {
        let row = SDLogSession(session: session)
        modelContext.insert(row)
        try modelContext.save()
        activeSessionRow = row
    }

    /// Every recorded session, newest first.
    public func sessions() throws -> [LogSession] {
        let descriptor = FetchDescriptor<SDLogSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)],
        )
        return try modelContext.fetch(descriptor).map(\.toValue)
    }

    /// The launch-attribution row, created from `LogSession.current()` when
    /// the app never called ``startSession(_:)`` explicitly.
    private func ensureActiveSession() throws -> SDLogSession {
        if let activeSessionRow {
            return activeSessionRow
        }
        let row = SDLogSession(session: .current())
        modelContext.insert(row)
        activeSessionRow = row
        return row
    }

    // MARK: LogSink

    public func defineScopes(_ scopes: [LogScope]) async {
        do {
            for scope in scopes {
                try upsertScopeRow(scope)
            }
            try modelContext.save()
        } catch {
            writeFailures += 1
            Self.failureLogger.error("Failed to persist \(scopes.count) scopes: \(error)")
        }
    }

    public func write(_ records: [LogRecord]) async {
        guard !records.isEmpty else { return }
        do {
            try persist(records)
            notifyChanged()
        } catch {
            writeFailures += 1
            Self.failureLogger.error("Failed to persist \(records.count) log events: \(error)")
        }
    }

    public func flush() async {
        // Every write commits in its own save; nothing is buffered here.
    }

    /// Persistence failures observed so far (also logged to OSLog).
    @_spi(Testing) public var writeFailureCount: Int {
        writeFailures
    }

    /// The next monotonic insertion sequence, resuming past the largest
    /// stored value on the first write of a launch.
    private func takeSequence() throws -> Int {
        if let nextSequence {
            self.nextSequence = nextSequence + 1
            return nextSequence
        }
        var descriptor = FetchDescriptor<SDLogEvent>(
            sortBy: [SortDescriptor(\.sequence, order: .reverse)],
        )
        descriptor.fetchLimit = 1
        let highest = try modelContext.fetch(descriptor).first?.sequence ?? -1
        nextSequence = highest + 2
        return highest + 1
    }

    private func persist(_ records: [LogRecord]) throws {
        let session = try ensureActiveSession()
        for record in records {
            let payload: Data
            do {
                payload = try JSONEncoder().encode(record.event)
            } catch {
                // Keep the row (message, level, scopes survive) — degraded
                // but handled.
                payload = Data()
                Self.failureLogger.warning(
                    "Payload for \(record.eventName) failed to encode: \(error)",
                )
            }
            let scopeRows = try record.scopes.map { try scopeRow(for: $0.rawValue) }
            let tagRows = try record.tags.map { key, value in
                try tagRow(for: LogTag(key: key, value: value))
            }
            let row = try SDLogEvent(
                eventID: record.id,
                date: record.date,
                sequence: takeSequence(),
                severity: record.level.severity,
                levelName: record.level.name,
                eventName: record.eventName,
                eventVersion: record.eventVersion,
                message: record.message,
                payload: payload,
                orderedScopeIDs: record.scopes.map(\.rawValue),
                sessionID: session.sessionID,
                spanID: record.spanID?.rawValue,
                scopes: scopeRows,
                tags: tagRows,
            )
            modelContext.insert(row)
        }
        try modelContext.save()
    }

    // MARK: Scopes

    /// All scopes ever defined, in no particular order.
    public func scopes() throws -> [LogScope] {
        try modelContext.fetch(FetchDescriptor<SDLogScope>()).map(Self.scopeValue)
    }

    /// Resolve one scope.
    public func scope(for id: ScopeID) throws -> LogScope? {
        try fetchScopeRow(id: id.rawValue).map(Self.scopeValue)
    }

    private static func scopeValue(_ row: SDLogScope) -> LogScope {
        LogScope(
            id: ScopeID(rawValue: row.scopeID),
            name: row.name,
            parentID: row.parentID.map(ScopeID.init(rawValue:)),
        )
    }

    /// Insert or update the row for `scope` (idempotent per scope ID).
    private func upsertScopeRow(_ scope: LogScope) throws {
        let row = try scopeRow(for: scope.id.rawValue)
        if row.name != scope.name {
            row.name = scope.name
        }
        if row.parentID != scope.parentID?.rawValue {
            row.parentID = scope.parentID?.rawValue
        }
    }

    /// Fetch-or-create a scope row. Records normally arrive after their
    /// scope definitions, but an unknown scope still gets a placeholder row
    /// (empty name) that a later definition fills in.
    private func scopeRow(for id: UUID) throws -> SDLogScope {
        if let cached = scopeRowCache[id] {
            return cached
        }
        if let existing = try fetchScopeRow(id: id) {
            scopeRowCache[id] = existing
            return existing
        }
        let row = SDLogScope(scopeID: id, name: "", parentID: nil)
        modelContext.insert(row)
        scopeRowCache[id] = row
        return row
    }

    private func fetchScopeRow(id: UUID) throws -> SDLogScope? {
        var descriptor = FetchDescriptor<SDLogScope>(
            predicate: #Predicate { $0.scopeID == id },
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    // MARK: Tags

    /// Fetch-or-create the shared row for a key/value tag pair.
    private func tagRow(for tag: LogTag) throws -> SDLogTag {
        if let cached = tagRowCache[tag] {
            return cached
        }
        let pair = SDLogTag.pairValue(key: tag.key.rawValue, value: tag.value)
        var descriptor = FetchDescriptor<SDLogTag>(
            predicate: #Predicate { $0.pair == pair },
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            tagRowCache[tag] = existing
            return existing
        }
        let row = SDLogTag(key: tag.key.rawValue, value: tag.value)
        modelContext.insert(row)
        tagRowCache[tag] = row
        return row
    }

    /// `subtree` plus every descendant, resolved against the stored
    /// hierarchy.
    private func subtreeIDs(of subtree: ScopeID) throws -> [UUID] {
        let rows = try modelContext.fetch(FetchDescriptor<SDLogScope>())
        var childrenByParent: [UUID: [UUID]] = [:]
        for row in rows {
            if let parent = row.parentID {
                childrenByParent[parent, default: []].append(row.scopeID)
            }
        }
        var result: [UUID] = []
        var frontier = [subtree.rawValue]
        while let next = frontier.popLast() {
            result.append(next)
            frontier.append(contentsOf: childrenByParent[next] ?? [])
        }
        return result
    }

    // MARK: Queries

    /// Events matching `query`, newest first.
    public func events(matching query: LogQuery) throws -> [StoredLogEvent] {
        let start = query.start ?? .distantPast
        let end = query.end ?? .distantFuture
        let minSeverity = query.minimumLevel?.severity ?? Int.min
        let filtersName = query.eventName != nil
        let name = query.eventName ?? ""
        let filtersSession = query.sessionID != nil
        let session = query.sessionID ?? UUID()
        let filtersSearch = !(query.messageContains ?? "").isEmpty
        let search = query.messageContains ?? ""
        let filtersScope = query.scope != nil
        let scopeIDs: [UUID] = switch query.scope {
            case let .exactly(id): [id.rawValue]
            case let .subtree(id): try subtreeIDs(of: id)
            case nil: []
        }
        let filtersTag = query.tag != nil
        let tagPair = query.tag.map {
            SDLogTag.pairValue(key: $0.key.rawValue, value: $0.value)
        } ?? ""

        let predicate = #Predicate<SDLogEvent> { event in
            event.date >= start && event.date <= end
                && event.severity >= minSeverity
                && (!filtersName || event.eventName == name)
                && (!filtersSession || event.sessionID == session)
                && (!filtersSearch || event.message.localizedStandardContains(search))
                && (!filtersScope || event.scopes.contains { scopeIDs.contains($0.scopeID) })
                && (!filtersTag || event.tags.contains { $0.pair == tagPair })
        }

        var descriptor = FetchDescriptor<SDLogEvent>(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\.date, order: .reverse),
                SortDescriptor(\.sequence, order: .reverse),
            ],
        )
        if let limit = query.limit {
            descriptor.fetchLimit = limit
        }
        if let offset = query.offset {
            descriptor.fetchOffset = offset
        }
        return try modelContext.fetch(descriptor).map(Self.eventValue)
    }

    /// Both halves of a span (begin and end events sharing `span`), newest
    /// first. Kept separate from ``events(matching:)`` so the hot general
    /// predicate stays small.
    public func events(inSpan span: SpanID) throws -> [StoredLogEvent] {
        let id: UUID? = span.rawValue
        let descriptor = FetchDescriptor<SDLogEvent>(
            predicate: #Predicate { $0.spanID == id },
            sortBy: [
                SortDescriptor(\.date, order: .reverse),
                SortDescriptor(\.sequence, order: .reverse),
            ],
        )
        return try modelContext.fetch(descriptor).map(Self.eventValue)
    }

    /// One persisted event by ID (for the tracer and inspectors).
    public func event(id: UUID) throws -> StoredLogEvent? {
        var descriptor = FetchDescriptor<SDLogEvent>(
            predicate: #Predicate { $0.eventID == id },
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map(Self.eventValue)
    }

    private static func eventValue(_ row: SDLogEvent) -> StoredLogEvent {
        StoredLogEvent(
            id: row.eventID,
            date: row.date,
            level: LogLevel(name: row.levelName, severity: row.severity),
            eventName: row.eventName,
            eventVersion: row.eventVersion,
            message: row.message,
            payload: row.payload,
            scopes: row.orderedScopeIDs.map(ScopeID.init(rawValue:)),
            tags: Dictionary(
                row.tags.map { (LogTagKey($0.key), $0.value) },
                uniquingKeysWith: { first, _ in first },
            ),
            spanID: row.spanID.map(SpanID.init(rawValue:)),
            sessionID: row.sessionID,
        )
    }

    // MARK: Retention

    /// Delete events older than `cutoff`; returns how many were removed.
    /// Scopes and sessions stay — they're tiny and keep old exports legible.
    public func pruneEvents(olderThan cutoff: Date) throws -> Int {
        let descriptor = FetchDescriptor<SDLogEvent>(
            predicate: #Predicate { $0.date < cutoff },
        )
        return try delete(modelContext.fetch(descriptor))
    }

    /// Keep only the newest `count` events; returns how many were removed.
    public func pruneEvents(keepingNewest count: Int) throws -> Int {
        var descriptor = FetchDescriptor<SDLogEvent>(
            sortBy: [
                SortDescriptor(\.date, order: .reverse),
                SortDescriptor(\.sequence, order: .reverse),
            ],
        )
        descriptor.fetchOffset = count
        return try delete(modelContext.fetch(descriptor))
    }

    /// Delete every stored event (developer tooling's "clear").
    public func deleteAllEvents() throws {
        _ = try delete(modelContext.fetch(FetchDescriptor<SDLogEvent>()))
    }

    private func delete(_ rows: [SDLogEvent]) throws -> Int {
        guard !rows.isEmpty else { return 0 }
        for row in rows {
            modelContext.delete(row)
        }
        try modelContext.save()
        notifyChanged()
        return rows.count
    }

    // MARK: Change notification

    /// Pings after every committed write or deletion — live viewers refresh
    /// off this signal.
    public func changes() -> AsyncStream<Void> {
        let id = UUID()
        return AsyncStream { continuation in
            changeObservers[id] = continuation
            continuation.onTermination = { _ in
                Task { await self.removeChangeObserver(id) }
            }
        }
    }

    private func removeChangeObserver(_ id: UUID) {
        changeObservers[id] = nil
    }

    private func notifyChanged() {
        for continuation in changeObservers.values {
            continuation.yield(())
        }
    }
}
