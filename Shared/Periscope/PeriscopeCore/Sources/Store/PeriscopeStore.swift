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
/// count in ``writeFailureCount`` rather than vanishing — and the failed
/// transaction rolls back so one poisoned batch can't wedge every save
/// after it.
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
    static let failureLogger = os.Logger(
        subsystem: "com.stuff.periscope",
        category: "PeriscopeStore",
    )

    /// This launch's session identity — survives write recovery, so events
    /// after a rollback still attribute to the same launch.
    private var activeSession: LogSession?
    private var activeSessionRow: SDLogSession?
    private var scopeRowCache: [UUID: SDLogScope] = [:]
    private var tagRowCache: [LogTag: SDLogTag] = [:]
    private var changeObservers: [UUID: AsyncStream<Void>.Continuation] = [:]
    var writeFailures = 0
    private var nextSequence: Int?

    #if DEBUG
        private var pendingWriteFailure: (any Error)?
    #endif

    /// The crash journal for this launch — created for on-disk stores and
    /// installed into `Periscope` when the store is added as a sink.
    /// Boxed so the `@ModelActor`-synthesized init stays usable and the
    /// pipeline can read it without an actor hop.
    private nonisolated let journalBox = OSAllocatedUnfairLock<LogJournal?>(initialState: nil)

    @_spi(Testing) public nonisolated var journal: LogJournal? {
        journalBox.withLock { $0 }
    }

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
    /// subsequent event is attributed to this launch. On-disk stores also
    /// open this launch's crash journal beside the database — the
    /// synchronous net `Periscope` writes through once the store is added
    /// as a sink.
    public static func make(storage: Storage, session: LogSession) async throws -> PeriscopeStore {
        let container = try makeContainer(storage: storage)
        let store = PeriscopeStore(modelContainer: container)
        // Ingest before the session starts: recovered span begans must be
        // in the store when startSession's orphan sweep runs, so a crashed
        // flow closes as .orphaned instead of vanishing.
        if storage == .onDisk {
            await store.ingestRecoveredJournals()
        }
        try await store.startSession(session)
        if storage == .onDisk {
            await store.openJournal(session: session)
        }
        return store
    }

    /// Test/preview factory: a fresh in-memory store per call. In-memory
    /// stores never journal — journaling is a durability feature, and
    /// recovery *is* persistence.
    @_spi(Testing) public static func inMemory(
        session: LogSession,
    ) async throws -> PeriscopeStore {
        try await make(storage: .inMemory, session: session)
    }

    /// Test factory: a fully journaling on-disk store rooted at an explicit
    /// URL, so tests exercise the durability path in isolated temporary
    /// directories.
    @_spi(Testing) public static func onDisk(
        databaseURL: URL,
        session: LogSession,
    ) async throws -> PeriscopeStore {
        let schema = Schema(PeriscopeSchema.models)
        let configuration = ModelConfiguration(schema: schema, url: databaseURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let store = PeriscopeStore(modelContainer: container)
        await store.ingestRecoveredJournals()
        try await store.startSession(session)
        await store.openJournal(session: session)
        return store
    }

    // MARK: Journal

    /// Where session journals live: `Periscope-Journals/<sessionID>/`
    /// beside the database.
    @_spi(Testing) public nonisolated func journalDirectory(forSession id: UUID) -> URL {
        journalsRoot.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    nonisolated var journalsRoot: URL {
        let databaseDirectory = modelContainer.configurations.first?.url
            .deletingLastPathComponent()
            ?? URL.applicationSupportDirectory
        return databaseDirectory.appendingPathComponent("Periscope-Journals", isDirectory: true)
    }

    /// Open this launch's journal. Degraded-but-handled on failure: an
    /// unjournalable disk must not take down logging, so the error logs
    /// and counts while the async pipeline keeps delivering.
    private func openJournal(session: LogSession) {
        do {
            let journal = try LogJournal(
                directory: journalDirectory(forSession: session.id),
                session: session,
            )
            journalBox.withLock { $0 = journal }
        } catch {
            writeFailures += 1
            Self.failureLogger.warning("Failed to open the crash journal: \(error)")
        }
    }

    // MARK: Sessions

    /// Record `session` as this launch's resource metadata; every event
    /// written afterwards references it. Starting a session also declares
    /// every earlier session dead: spans they left open (and whose policy
    /// is `.endsWithProcess`) close as `.orphaned`.
    public func startSession(_ session: LogSession) throws {
        activeSession = session
        let row = SDLogSession(session: session)
        modelContext.insert(row)
        do {
            try modelContext.save()
        } catch {
            recoverFromFailedWrite()
            throw error
        }
        activeSessionRow = row
        closeOrphanedSpans(startedSessionID: session.id)
    }

    /// Close spans that earlier sessions began but never ended. The begin
    /// payload's ``SpanRelaunchPolicy`` decides: `.endsWithProcess` spans
    /// get a synthetic ``SpanEnded`` (`.orphaned`, duration unknowable —
    /// the process died at an unknown point); `.survivesRelaunch` spans
    /// stay open. Runs degraded-but-handled: a sweep failure logs and
    /// counts, it never fails the session start.
    private func closeOrphanedSpans(startedSessionID: UUID) {
        do {
            let beganName = SpanBegan.eventName
            let endedName = SpanEnded.eventName

            // This runs on the launch path with weeks of history behind it,
            // so the began/ended passes fetch only the spanID column; full
            // rows (payload for the policy, tags for attribution) load only
            // for the few orphan candidates.
            var beganDescriptor = FetchDescriptor<SDLogEvent>(
                predicate: #Predicate {
                    $0.eventName == beganName && $0.sessionID != startedSessionID
                },
            )
            beganDescriptor.propertiesToFetch = [\.spanID]
            let beganIDs = try modelContext.fetch(beganDescriptor).compactMap(\.spanID)
            guard !beganIDs.isEmpty else { return }

            var endedDescriptor = FetchDescriptor<SDLogEvent>(
                predicate: #Predicate { $0.eventName == endedName },
            )
            endedDescriptor.propertiesToFetch = [\.spanID]
            let endedSpanIDs = try Set(modelContext.fetch(endedDescriptor).compactMap(\.spanID))

            let candidateIDs: [UUID?] = beganIDs.filter { !endedSpanIDs.contains($0) }
            guard !candidateIDs.isEmpty else { return }

            let began = try modelContext.fetch(Self.readDescriptor(
                predicate: #Predicate {
                    $0.eventName == beganName && candidateIDs.contains($0.spanID)
                },
            ))

            var orphans: [LogRecord] = []
            for row in began {
                guard let spanID = row.spanID else { continue }
                // A payload that no longer decodes can't prove it wanted to
                // survive — closing it is the honest fallback.
                let event = try? JSONDecoder().decode(SpanBegan.self, from: row.payload)
                if event?.relaunchPolicy == .survivesRelaunch {
                    continue
                }
                orphans.append(LogRecord(
                    date: Date(),
                    event: SpanEnded(
                        spanID: SpanID(rawValue: spanID),
                        name: event?.name ?? row.message,
                        duration: nil,
                        exit: .orphaned,
                    ),
                    scopes: row.orderedScopeIDs.map(ScopeID.init(rawValue:)),
                    tags: Self.tags(from: row),
                ))
            }
            guard !orphans.isEmpty else { return }
            try persist(orphans)
            notifyChanged()
        } catch {
            recoverFromFailedWrite()
            writeFailures += 1
            Self.failureLogger.warning("Failed to close orphaned spans: \(error)")
        }
    }

    /// Every recorded session, newest first.
    public func sessions() throws -> [LogSession] {
        let descriptor = FetchDescriptor<SDLogSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)],
        )
        return try modelContext.fetch(descriptor).map(\.toValue)
    }

    /// The launch-attribution row for ``activeSession`` (defaulting to
    /// `LogSession.current()` when the app never called
    /// ``startSession(_:)``). Refetches a committed row when the cached
    /// reference was dropped by write recovery, so the session identity
    /// never forks.
    private func ensureActiveSession() throws -> SDLogSession {
        if let activeSessionRow {
            return activeSessionRow
        }
        let session = activeSession ?? .current()
        activeSession = session
        let id = session.id
        var descriptor = FetchDescriptor<SDLogSession>(
            predicate: #Predicate { $0.sessionID == id },
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            activeSessionRow = existing
            return existing
        }
        let row = SDLogSession(session: session)
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
            try throwInjectedFailureIfPending()
            try modelContext.save()
        } catch {
            recoverFromFailedWrite()
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
            recoverFromFailedWrite()
            writeFailures += 1
            Self.failureLogger.error("Failed to persist \(records.count) log events: \(error)")
            persistWriteFailureMarker(
                lostRecordCount: records.count,
                reason: String(describing: error),
            )
        }
    }

    /// After a rolled-back write, persist a ``StoreWriteFailed`` marker so
    /// the durable history is honest about its own gap — the batch is gone,
    /// but the store says so where the viewer can see it. Best-effort: if
    /// the marker's own tiny save also fails, the OSLog line above is the
    /// last signal (no recursion).
    private func persistWriteFailureMarker(lostRecordCount: Int, reason: String) {
        let marker = LogRecord(
            date: Date(),
            event: StoreWriteFailed(lostRecordCount: lostRecordCount, reason: reason),
            scopes: [],
        )
        do {
            try persist([marker])
            notifyChanged()
        } catch {
            recoverFromFailedWrite()
            Self.failureLogger.error("Failed to persist the write-failure marker: \(error)")
        }
    }

    public func flush() async {
        // Every write commits in its own save; nothing is buffered here.
    }

    /// Persistence failures observed so far (also logged to OSLog).
    @_spi(Testing) public var writeFailureCount: Int {
        writeFailures
    }

    /// Registered `changes()` observers — lets tests assert subscription
    /// lifecycles (e.g. that a rebound viewer released its old stream).
    @_spi(Testing) public var changeObserverCount: Int {
        changeObservers.count
    }

    #if DEBUG
        /// Test seam: the next staged write (`write`, `defineScopes`, or a
        /// deletion) fails with `error` just before its save would commit,
        /// exercising the rollback/recovery path.
        @_spi(Testing) public func injectNextWriteFailure(_ error: any Error) {
            pendingWriteFailure = error
        }
    #endif

    /// Discard the failed transaction so a poisoned batch can't wedge every
    /// save after it, and drop state that may reference rolled-back rows:
    /// the row caches, and the session-row reference (`ensureActiveSession`
    /// refetches or reinserts the same session identity on the next write).
    func recoverFromFailedWrite() {
        modelContext.rollback()
        scopeRowCache.removeAll()
        tagRowCache.removeAll()
        activeSessionRow = nil
    }

    /// Throws the injected test failure, if any (DEBUG-only seam; a no-op
    /// in release).
    func throwInjectedFailureIfPending() throws {
        #if DEBUG
            if let pendingWriteFailure {
                self.pendingWriteFailure = nil
                throw pendingWriteFailure
            }
        #endif
    }

    /// The next monotonic insertion sequence, resuming past the largest
    /// stored value on the first write of a launch.
    func takeSequence() throws -> Int {
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
            let tagRows = try record.tags.map { tag in
                try tagRow(for: tag)
            }
            let attachmentRows = record.attachments.enumerated().map { index, attachment in
                SDLogAttachment(
                    name: attachment.name,
                    contentType: attachment.contentType.mimeType,
                    index: index,
                    data: attachment.data,
                )
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
                spanExitMode: record.spanExit?.mode.rawValue,
                callFunction: record.callSite?.function,
                callFileID: record.callSite?.fileID,
                externalID: record.externalID,
                scopes: scopeRows,
                tags: tagRows,
                attachments: attachmentRows,
            )
            modelContext.insert(row)
        }
        try throwInjectedFailureIfPending()
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
    func scopeRow(for id: UUID) throws -> SDLogScope {
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
    /// The typed tags for an event row, key-sorted for deterministic order
    /// (the relationship itself is unordered).
    private static func tags(from row: SDLogEvent) -> [LogTag] {
        row.tags
            .map { tagRow in
                LogTag(
                    key: LogTagKey(tagRow.key),
                    value: LogTagValue(kind: tagRow.valueKind, stored: tagRow.value),
                )
            }
            .sorted { $0.key.rawValue < $1.key.rawValue }
    }

    func tagRow(for tag: LogTag) throws -> SDLogTag {
        if let cached = tagRowCache[tag] {
            return cached
        }
        let pair = tag.pair
        var descriptor = FetchDescriptor<SDLogTag>(
            predicate: #Predicate { $0.pair == pair },
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            tagRowCache[tag] = existing
            return existing
        }
        let row = SDLogTag(tag: tag)
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
        let filtersTags = !query.tags.isEmpty
        let tagPairs = query.tags.map(\.pair)
        let filtersExit = query.spanExitMode != nil
        let exitMode: String? = query.spanExitMode?.rawValue
        let filtersExternalID = query.externalID != nil
        let externalID: String? = query.externalID
        let filtersAfterSequence = query.afterSequence != nil
        let afterSequence = query.afterSequence ?? Int.min

        let predicate = Self.eventsPredicate(
            start: start,
            end: end,
            minSeverity: minSeverity,
            filtersName: filtersName,
            name: name,
            filtersSession: filtersSession,
            session: session,
            filtersExit: filtersExit,
            exitMode: exitMode,
            filtersExternalID: filtersExternalID,
            externalID: externalID,
            filtersSearch: filtersSearch,
            search: search,
            filtersScope: filtersScope,
            scopeIDs: scopeIDs,
            filtersTags: filtersTags,
            tagPairs: tagPairs,
            filtersAfterSequence: filtersAfterSequence,
            afterSequence: afterSequence,
        )

        var descriptor = Self.readDescriptor(
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

    /// The full filter predicate, hand-built in the shape `#Predicate`
    /// would expand to — but as *statements*, one small `let` per
    /// condition. A single macro expression with this many conditions is
    /// one giant inference tree, and it exceeds the type-checker's budget
    /// on slower machines (CI failed on what compiled locally); statement
    /// form type-checks each condition independently in milliseconds and
    /// scales linearly with future filters.
    private static func eventsPredicate(
        start: Date,
        end: Date,
        minSeverity: Int,
        filtersName: Bool,
        name: String,
        filtersSession: Bool,
        session: UUID,
        filtersExit: Bool,
        exitMode: String?,
        filtersExternalID: Bool,
        externalID: String?,
        filtersSearch: Bool,
        search: String,
        filtersScope: Bool,
        scopeIDs: [UUID],
        filtersTags: Bool,
        tagPairs: [String],
        filtersAfterSequence: Bool,
        afterSequence: Int,
    ) -> Predicate<SDLogEvent> {
        Predicate<SDLogEvent>({ event in
            let afterStart = PredicateExpressions.build_Comparison(
                lhs: PredicateExpressions.build_KeyPath(
                    root: PredicateExpressions.build_Arg(event),
                    keyPath: \.date,
                ),
                rhs: PredicateExpressions.build_Arg(start),
                op: .greaterThanOrEqual,
            )
            let beforeEnd = PredicateExpressions.build_Comparison(
                lhs: PredicateExpressions.build_KeyPath(
                    root: PredicateExpressions.build_Arg(event),
                    keyPath: \.date,
                ),
                rhs: PredicateExpressions.build_Arg(end),
                op: .lessThanOrEqual,
            )
            let atOrAboveFloor = PredicateExpressions.build_Comparison(
                lhs: PredicateExpressions.build_KeyPath(
                    root: PredicateExpressions.build_Arg(event),
                    keyPath: \.severity,
                ),
                rhs: PredicateExpressions.build_Arg(minSeverity),
                op: .greaterThanOrEqual,
            )
            // Each optional filter keeps the `!filters || matches` shape
            // the macro version used.
            let matchesName = PredicateExpressions.build_Disjunction(
                lhs: PredicateExpressions.build_Negation(
                    PredicateExpressions.build_Arg(filtersName),
                ),
                rhs: PredicateExpressions.build_Equal(
                    lhs: PredicateExpressions.build_KeyPath(
                        root: PredicateExpressions.build_Arg(event),
                        keyPath: \.eventName,
                    ),
                    rhs: PredicateExpressions.build_Arg(name),
                ),
            )
            let matchesSession = PredicateExpressions.build_Disjunction(
                lhs: PredicateExpressions.build_Negation(
                    PredicateExpressions.build_Arg(filtersSession),
                ),
                rhs: PredicateExpressions.build_Equal(
                    lhs: PredicateExpressions.build_KeyPath(
                        root: PredicateExpressions.build_Arg(event),
                        keyPath: \.sessionID,
                    ),
                    rhs: PredicateExpressions.build_Arg(session),
                ),
            )
            let matchesExit = PredicateExpressions.build_Disjunction(
                lhs: PredicateExpressions.build_Negation(
                    PredicateExpressions.build_Arg(filtersExit),
                ),
                rhs: PredicateExpressions.build_Equal(
                    lhs: PredicateExpressions.build_KeyPath(
                        root: PredicateExpressions.build_Arg(event),
                        keyPath: \.spanExitMode,
                    ),
                    rhs: PredicateExpressions.build_Arg(exitMode),
                ),
            )
            let matchesExternalID = PredicateExpressions.build_Disjunction(
                lhs: PredicateExpressions.build_Negation(
                    PredicateExpressions.build_Arg(filtersExternalID),
                ),
                rhs: PredicateExpressions.build_Equal(
                    lhs: PredicateExpressions.build_KeyPath(
                        root: PredicateExpressions.build_Arg(event),
                        keyPath: \.externalID,
                    ),
                    rhs: PredicateExpressions.build_Arg(externalID),
                ),
            )
            let matchesSearch = PredicateExpressions.build_Disjunction(
                lhs: PredicateExpressions.build_Negation(
                    PredicateExpressions.build_Arg(filtersSearch),
                ),
                rhs: PredicateExpressions.build_localizedStandardContains(
                    PredicateExpressions.build_KeyPath(
                        root: PredicateExpressions.build_Arg(event),
                        keyPath: \.message,
                    ),
                    PredicateExpressions.build_Arg(search),
                ),
            )
            let matchesScope = PredicateExpressions.build_Disjunction(
                lhs: PredicateExpressions.build_Negation(
                    PredicateExpressions.build_Arg(filtersScope),
                ),
                rhs: PredicateExpressions.build_contains(
                    PredicateExpressions.build_KeyPath(
                        root: PredicateExpressions.build_Arg(event),
                        keyPath: \.scopes,
                    ),
                ) { scope in
                    PredicateExpressions.build_contains(
                        PredicateExpressions.build_Arg(scopeIDs),
                        PredicateExpressions.build_KeyPath(
                            root: PredicateExpressions.build_Arg(scope),
                            keyPath: \.scopeID,
                        ),
                    )
                },
            )
            // AND across the requested tags without a dynamic expression
            // tree: an event row can't carry duplicate pairs, so "matches
            // all N tags" is "N of its tag rows have a pair in the list".
            let matchesTag = PredicateExpressions.build_Disjunction(
                lhs: PredicateExpressions.build_Negation(
                    PredicateExpressions.build_Arg(filtersTags),
                ),
                rhs: PredicateExpressions.build_Equal(
                    lhs: PredicateExpressions.build_KeyPath(
                        root: PredicateExpressions.build_filter(
                            PredicateExpressions.build_KeyPath(
                                root: PredicateExpressions.build_Arg(event),
                                keyPath: \.tags,
                            ),
                        ) { tag in
                            PredicateExpressions.build_contains(
                                PredicateExpressions.build_Arg(tagPairs),
                                PredicateExpressions.build_KeyPath(
                                    root: PredicateExpressions.build_Arg(tag),
                                    keyPath: \.pair,
                                ),
                            )
                        },
                        keyPath: \.count,
                    ),
                    rhs: PredicateExpressions.build_Arg(tagPairs.count),
                ),
            )
            // The incremental "newer than" cursor: strictly greater, so the
            // event a viewer last merged doesn't come back on the next fetch.
            let matchesAfterSequence = PredicateExpressions.build_Disjunction(
                lhs: PredicateExpressions.build_Negation(
                    PredicateExpressions.build_Arg(filtersAfterSequence),
                ),
                rhs: PredicateExpressions.build_Comparison(
                    lhs: PredicateExpressions.build_KeyPath(
                        root: PredicateExpressions.build_Arg(event),
                        keyPath: \.sequence,
                    ),
                    rhs: PredicateExpressions.build_Arg(afterSequence),
                    op: .greaterThan,
                ),
            )

            let dates = PredicateExpressions.build_Conjunction(
                lhs: afterStart,
                rhs: beforeEnd,
            )
            let base = PredicateExpressions.build_Conjunction(
                lhs: dates,
                rhs: atOrAboveFloor,
            )
            let named = PredicateExpressions.build_Conjunction(
                lhs: base,
                rhs: matchesName,
            )
            let sessioned = PredicateExpressions.build_Conjunction(
                lhs: named,
                rhs: matchesSession,
            )
            let exited = PredicateExpressions.build_Conjunction(
                lhs: sessioned,
                rhs: matchesExit,
            )
            let externallyIdentified = PredicateExpressions.build_Conjunction(
                lhs: exited,
                rhs: matchesExternalID,
            )
            let searched = PredicateExpressions.build_Conjunction(
                lhs: externallyIdentified,
                rhs: matchesSearch,
            )
            let scoped = PredicateExpressions.build_Conjunction(
                lhs: searched,
                rhs: matchesScope,
            )
            let tagged = PredicateExpressions.build_Conjunction(
                lhs: scoped,
                rhs: matchesTag,
            )
            return PredicateExpressions.build_Conjunction(
                lhs: tagged,
                rhs: matchesAfterSequence,
            )
        })
    }

    /// Both halves of a span (begin and end events sharing `span`), newest
    /// first. Kept separate from ``events(matching:)`` so the hot general
    /// predicate stays small.
    public func events(inSpan span: SpanID) throws -> [StoredLogEvent] {
        let id: UUID? = span.rawValue
        let descriptor = Self.readDescriptor(
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
        try fetchEventRow(id: id).map(Self.eventValue)
    }

    /// An event's attachments with their bytes loaded, in attach order.
    /// Queried events carry only ``LogAttachmentInfo`` so list fetches
    /// never pull blobs.
    public func attachments(forEvent id: UUID) throws -> [LogAttachment] {
        guard let row = try fetchEventRow(id: id) else { return [] }
        return row.attachments
            .sorted { $0.index < $1.index }
            .map { row in
                LogAttachment(
                    name: row.name,
                    contentType: LogAttachment.ContentType(mimeType: row.contentType),
                    data: row.data,
                )
            }
    }

    private func fetchEventRow(id: UUID) throws -> SDLogEvent? {
        var descriptor = Self.readDescriptor(predicate: #Predicate { $0.eventID == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// The descriptor for reads that map rows to values: `eventValue`
    /// touches the `tags` and `attachments` relationships on every row, so
    /// prefetch them — otherwise each row faults each relationship in its
    /// own round trip (N+1). Attachment *blobs* still load lazily; only the
    /// metadata rows prefetch.
    private static func readDescriptor(
        predicate: Predicate<SDLogEvent>? = nil,
        sortBy: [SortDescriptor<SDLogEvent>] = [],
    ) -> FetchDescriptor<SDLogEvent> {
        var descriptor = FetchDescriptor<SDLogEvent>(predicate: predicate, sortBy: sortBy)
        descriptor.relationshipKeyPathsForPrefetching = [\.tags, \.attachments]
        return descriptor
    }

    private static func eventValue(_ row: SDLogEvent) -> StoredLogEvent {
        StoredLogEvent(
            id: row.eventID,
            date: row.date,
            sequence: row.sequence,
            level: LogLevel(name: row.levelName, severity: row.severity),
            eventName: row.eventName,
            eventVersion: row.eventVersion,
            message: row.message,
            payload: row.payload,
            scopes: row.orderedScopeIDs.map(ScopeID.init(rawValue:)),
            tags: tags(from: row),
            spanID: row.spanID.map(SpanID.init(rawValue:)),
            spanExitMode: row.spanExitMode.flatMap(SpanExit.Mode.init(rawValue:)),
            callSite: row.callFunction.flatMap { function in
                row.callFileID.map { LogCallSite(function: function, fileID: $0) }
            },
            externalID: row.externalID,
            attachments: row.attachments
                .sorted { $0.index < $1.index }
                .map { row in
                    LogAttachmentInfo(
                        name: row.name,
                        contentType: LogAttachment.ContentType(mimeType: row.contentType),
                    )
                },
            sessionID: row.sessionID,
        )
    }

    // MARK: Retention

    /// Delete events older than `cutoff`; returns how many were removed.
    /// Metadata the deletion orphans — event-less sessions, tag rows, and
    /// scope branches — goes with it, so long-term growth stays bounded by
    /// the events actually retained.
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
        do {
            try throwInjectedFailureIfPending()
            try modelContext.save()
        } catch {
            // Roll the staged deletions back — otherwise the next unrelated
            // save would silently commit them.
            recoverFromFailedWrite()
            throw error
        }
        do {
            // A second save, after the deletions committed: inverse
            // relationships (`scope.events`, `tag.events`) only reflect
            // removed rows once saved, so orphanhood isn't provable inside
            // the same transaction.
            try pruneOrphanedMetadata()
            try modelContext.save()
        } catch {
            recoverFromFailedWrite()
            throw error
        }
        notifyChanged()
        return rows.count
    }

    /// Remove metadata rows the deletion just orphaned, in the same save —
    /// without this, retention only bounds the events table: one session
    /// row per launch and one tag row per distinct pair (unbounded when
    /// values are entity IDs) accumulate forever.
    ///
    /// - Sessions with no remaining events go, except the active launch's.
    /// - Tag rows with no remaining events go (their cache entries too).
    /// - Scopes go leaf-first when they have no events *and* no children,
    ///   so ancestors of still-populated scopes survive for path
    ///   resolution.
    private func pruneOrphanedMetadata() throws {
        for session in try modelContext.fetch(FetchDescriptor<SDLogSession>()) {
            let sessionID = session.sessionID
            guard sessionID != activeSession?.id else { continue }
            var events = FetchDescriptor<SDLogEvent>(
                predicate: #Predicate { $0.sessionID == sessionID },
            )
            events.fetchLimit = 1
            if try modelContext.fetchCount(events) == 0 {
                modelContext.delete(session)
            }
        }

        for tag in try modelContext.fetch(FetchDescriptor<SDLogTag>()) where tag.events.isEmpty {
            tagRowCache[LogTag(
                key: LogTagKey(tag.key),
                value: LogTagValue(kind: tag.valueKind, stored: tag.value),
            )] = nil
            modelContext.delete(tag)
        }

        var scopes = try modelContext.fetch(FetchDescriptor<SDLogScope>())
        var removedLeaf = true
        while removedLeaf {
            removedLeaf = false
            let parentIDs = Set(scopes.compactMap(\.parentID))
            scopes.removeAll { scope in
                guard scope.events.isEmpty, !parentIDs.contains(scope.scopeID) else {
                    return false
                }
                scopeRowCache[scope.scopeID] = nil
                modelContext.delete(scope)
                removedLeaf = true
                return true
            }
        }
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

    func notifyChanged() {
        for continuation in changeObservers.values {
            continuation.yield(())
        }
    }
}
