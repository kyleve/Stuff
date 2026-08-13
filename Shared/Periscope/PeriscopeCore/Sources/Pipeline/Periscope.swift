import Foundation
import os

/// The Periscope system: the recorder every `Log` emits into, and the
/// pipeline that fans records out to ``LogSink``s.
///
/// Emitting never blocks the caller — `record` appends to a lock-guarded
/// pending queue and returns; a background drain task delivers batches to
/// each sink in order. The system also keeps a bounded buffer of recent
/// records for live UI (toasts, viewers) via ``recentRecords()`` and
/// ``liveRecords()``.
///
/// Around the pipeline the system owns the policies:
///
/// - **Level floors** — ``minimumLevel`` plus per-subtree overrides
///   (``setMinimumLevel(_:forSubtree:)``), checked at emit time before any
///   other work.
/// - **Flush policy** — records at ``Configuration/flushThreshold`` or above
///   trigger an automatic ``flush()`` so pre-crash context reaches disk.
/// - **Drop policy** — the pending queue is bounded by
///   ``Configuration/pendingBufferCapacity``; on overflow the oldest records
///   drop and a synthetic ``DroppedEvents`` record marks the gap. Scope
///   definitions and span began/ended pairs are exempt — pairs never split.
/// - **Ambient state** — `.state` ``AmbientEvent``s fold into a running
///   ``AmbientSnapshot``, and every record is stamped with it, so any event
///   can be joined to what the system was doing at that moment. Folding
///   outlives the admission gates: a floor-discarded ambient event still
///   folds (floors route, they don't scrub), and a redaction-suppressed one
///   clears its kind from the snapshot — the stamped state never goes stale
///   because an ambient event was kept out of the record stream.
/// - **Redaction** — ``Configuration/redact`` transforms (or suppresses)
///   every record before it is buffered or delivered anywhere. Span
///   began/ended records are transform-only: suppression falls back to a
///   stripped copy, so redaction can't split a pair.
///
/// Most apps use ``shared`` (preconfigured with an ``OSLogSink``) and add
/// their persistence sink at startup; tests build private systems.
public final class Periscope: LogRecorder, Sendable {
    /// The process-wide system, mirroring to OSLog under the main bundle's
    /// identifier. Add further sinks (e.g. the SwiftData store) at startup.
    public static let shared = Periscope(
        configuration: Configuration(),
        sinks: [OSLogSink(subsystem: Bundle.main.bundleIdentifier ?? "com.stuff.periscope")],
    )

    public struct Configuration: Sendable {
        /// Maximum records retained in the recent-records buffer.
        public var recentBufferCapacity: Int

        /// Maximum records queued for sink delivery; on overflow the oldest
        /// drop (scope definitions and span began/ended records never
        /// drop) and a ``DroppedEvents`` record reports the gap.
        public var pendingBufferCapacity: Int

        /// Maximum records buffered per ``liveRecords()`` observer that
        /// falls behind; the oldest buffered records drop first, so a slow
        /// or stuck consumer sees the newest activity instead of growing
        /// memory without bound.
        public var liveBufferCapacity: Int

        /// Records at this level or above trigger an automatic ``flush()``,
        /// so the most important events don't sit in sink buffers when the
        /// process dies.
        public var flushThreshold: LogLevel

        /// Applied to every admitted record before it is buffered or
        /// delivered. Return a transformed record to scrub PII, or `nil`
        /// to suppress the record entirely. `nil` hook means no redaction.
        ///
        /// Runs only for records that pass the level floors — floors apply
        /// to the record *as emitted* (redaction is content scrubbing, not
        /// routing), and redaction code never touches records the floor
        /// discards.
        ///
        /// Span began/ended records are *transform-only*: returning `nil`
        /// for one records a stripped copy instead (tags and attachments
        /// dropped, a `SpanEnded`'s freeform exit reason blanked) — a
        /// suppressed half would strand its partner. Use level floors to
        /// silence spans.
        public var redact: (@Sendable (LogRecord) -> LogRecord?)?

        public init(
            recentBufferCapacity: Int = 500,
            pendingBufferCapacity: Int = 5000,
            liveBufferCapacity: Int = 256,
            flushThreshold: LogLevel = .error,
            redact: (@Sendable (LogRecord) -> LogRecord?)? = nil,
        ) {
            self.recentBufferCapacity = recentBufferCapacity
            self.pendingBufferCapacity = pendingBufferCapacity
            self.liveBufferCapacity = liveBufferCapacity
            self.flushThreshold = flushThreshold
            self.redact = redact
        }
    }

    /// A registered sink's handle, returned by ``add(sink:)`` and consumed by
    /// ``remove(_:)``.
    ///
    /// A token rather than the sink itself because ``LogSink`` is not
    /// class-constrained: a struct sink has no identity to match on, and two
    /// value sinks that compare equal would be indistinguishable. Registration
    /// mints one identity per `add`, so removing one of two identical sinks
    /// removes exactly the one that token registered.
    public struct SinkToken: Hashable, Sendable {
        private let id: UUID

        fileprivate init() {
            id = UUID()
        }
    }

    /// A sink and the token it was registered under.
    private struct RegisteredSink {
        let token: SinkToken
        let sink: any LogSink
    }

    /// The synthetic event reporting records dropped by the overflow policy.
    public struct DroppedEvents: LogEvent {
        public static let eventName = "dropped-events"

        public let count: Int

        public var level: LogLevel {
            .warning
        }

        public var message: String {
            "\(count) log event(s) dropped before delivery"
        }

        public var remoteFields: [RemoteLogField] {
            [RemoteLogField(key: RemoteLogFieldKey("count"), value: .count(count))]
        }

        public init(count: Int) {
            self.count = count
        }
    }

    /// One entry in the ordered pending queue. A single queue keeps scope
    /// definitions strictly before the records that reference them.
    private enum PendingItem {
        case scope(LogScope)
        case record(LogRecord)
    }

    private struct State {
        var scopes: [ScopeID: LogScope] = [:]
        var sinks: [RegisteredSink] = []
        var pending: [PendingItem] = []
        var pendingRecordCount = 0
        var droppedCount = 0
        var recent: [LogRecord] = []
        var observers: [UUID: AsyncStream<LogRecord>.Continuation] = [:]
        var globalFloor: LogLevel?
        var subtreeFloors: [ScopeID: LogLevel] = [:]
        var openSpans: [SpanKey: OpenSpan] = [:]
        var ambientSources: [any AmbientEventSource] = []
        /// The running ambient state, folded from `.state` ambient events
        /// and stamped onto every record — see `stamped(_:in:)`.
        var ambient: AmbientSnapshot?
        var inspectModeEnabled = false
        var inspectObservers: [UUID: AsyncStream<Bool>.Continuation] = [:]
        /// The crash journal, installed when a `PeriscopeStore` sink is
        /// added; every buffered record appends to it synchronously.
        var journal: LogJournal?
        /// Stamped under this lock so journal replay can restore buffer
        /// order even though the file appends happen outside it.
        var journalSequence = 0
        /// The active drain task; `nil` exactly when nothing is draining.
        var drainTask: Task<Void, Never>?
        /// The span watchdog. Generation-tagged: respawning with an earlier
        /// wake time invalidates the old task so it can't clobber state.
        var watchdogTask: Task<Void, Never>?
        var watchdogGeneration = 0
        var watchdogWakeAt: ContinuousClock.Instant?
        /// The active auto-flush task; `nil` exactly when none is running.
        var autoFlushTask: Task<Void, Never>?
        /// A qualifying record arrived while an auto-flush was in flight;
        /// one follow-up flush covers every such record.
        var autoFlushPending = false
    }

    /// The scope Periscope's own synthetic events (drop reports) log under.
    public let systemScope = LogScope.root(named: "Periscope")

    public let configuration: Configuration
    private let state: OSAllocatedUnfairLock<State>

    /// Backs `LogContextProviding` — see `instanceLog(for:)`.
    let instanceScopes = InstanceScopeRegistry()

    public init(configuration: Configuration, sinks: [any LogSink]) {
        precondition(
            configuration.recentBufferCapacity > 0,
            "recentBufferCapacity must be positive",
        )
        precondition(
            configuration.pendingBufferCapacity > 0,
            "pendingBufferCapacity must be positive",
        )
        precondition(
            configuration.liveBufferCapacity > 0,
            "liveBufferCapacity must be positive",
        )
        self.configuration = configuration
        state = OSAllocatedUnfairLock(
            initialState: State(sinks: sinks.map { RegisteredSink(token: SinkToken(), sink: $0) }),
        )
        defineScope(systemScope)
    }

    // MARK: Sinks

    /// Register a sink. All scopes defined so far are replayed to the
    /// pipeline so the new sink can resolve every record it will see. The
    /// replay is *prepended*: records already pending must not reach the
    /// new sink ahead of the scopes they reference (existing sinks see the
    /// definitions again — idempotence is part of the sink contract).
    ///
    /// The returned token detaches this registration again via
    /// ``remove(_:)``; callers that keep a sink for the process lifetime can
    /// discard it.
    @discardableResult
    public func add(sink: some LogSink) -> SinkToken {
        let token = SinkToken()
        state.withLock { state in
            state.sinks.append(RegisteredSink(token: token, sink: sink))
            state.pending.insert(
                contentsOf: state.scopes.values.map(PendingItem.scope),
                at: 0,
            )
        }
        // Journaling requires a store: the store owns the journal (its
        // directory and session), and recovery is persistence. Adding one
        // turns the emit-side tap on.
        if let store = sink as? PeriscopeStore, let journal = store.journal {
            install(journal: journal)
        }
        scheduleDrainIfNeeded()
        return token
    }

    /// Detach the sink `token` registered. When this returns, the sink has
    /// received every record emitted before the call, has been flushed, and
    /// will receive nothing further.
    ///
    /// Both halves of that need the drain, which is why removal is `async`
    /// and brackets the deregistration with a wait:
    ///
    /// 1. Wait out the in-flight drain, so records already queued reach the
    ///    sink while it is still registered — dropping it first would strand
    ///    them, since nothing will deliver them to it afterwards.
    /// 2. Drop the registration under the lock, so no later drain sees it.
    /// 3. Wait again: a drain that started between the two is delivering
    ///    against a snapshot taken before the removal.
    ///
    /// A record emitted *concurrently* with the call may land on either side
    /// of it; the guarantee is about records emitted before it starts and
    /// after it returns. An unknown or already-removed token is a no-op.
    ///
    /// A removed store also takes its crash journal with it: the journal is
    /// the emit-side tap `add(sink:)` installed on that store's behalf, and
    /// leaving it installed would keep journaling records to a store no
    /// longer in the pipeline.
    public func remove(_ token: SinkToken) async {
        let isRegistered = state.withLock { state in
            state.sinks.contains { $0.token == token }
        }
        guard isRegistered else { return }

        await drainInFlightWork()
        let removed: (any LogSink)? = state.withLock { state in
            guard let index = state.sinks.firstIndex(where: { $0.token == token }) else {
                return nil
            }
            let removed = state.sinks.remove(at: index).sink
            if let store = removed as? PeriscopeStore, store.journal === state.journal {
                state.journal = nil
            }
            return removed
        }
        guard let removed else { return }
        await drainInFlightWork()
        await removed.flush()
    }

    /// Install the crash journal: every subsequent buffered record appends
    /// to it synchronously, and the scopes seen so far replay into it (a
    /// recovered record needs its hierarchy).
    @_spi(Testing) public func install(journal: LogJournal) {
        let scopes = state.withLock { state in
            state.journal = journal
            return Array(state.scopes.values)
        }
        for scope in scopes {
            journal.append(scope: scope)
        }
    }

    // MARK: Level floors

    /// The global minimum level; records below it are discarded at emit.
    /// `nil` (the default) records everything. Subtree overrides set via
    /// ``setMinimumLevel(_:forSubtree:)`` take precedence within their
    /// subtree.
    public var minimumLevel: LogLevel? {
        get { state.withLock(\.globalFloor) }
        set { state.withLock { $0.globalFloor = newValue } }
    }

    /// Override the minimum level for a scope and all its descendants —
    /// quiet a noisy subsystem, or open the floor for one area while the
    /// global floor stays high. Pass `nil` to clear the override. The
    /// nearest overridden ancestor wins.
    public func setMinimumLevel(_ level: LogLevel?, forSubtree scope: ScopeID) {
        state.withLock { $0.subtreeFloors[scope] = level }
    }

    /// Whether a record at `level` in `scopes` would be recorded. `Log`
    /// checks this before rendering freeform messages, so filtered-out
    /// logging skips string construction entirely. A record passes when
    /// *any* of its scopes admits it — a linked record stays visible as
    /// long as one of its contexts wants it.
    public func shouldRecord(level: LogLevel, scopes: [ScopeID]) -> Bool {
        state.withLock { state in
            Self.passesFloor(level: level, scopes: scopes, state: state)
        }
    }

    private static func passesFloor(level: LogLevel, scopes: [ScopeID], state: State) -> Bool {
        guard !state.subtreeFloors.isEmpty || state.globalFloor != nil else { return true }
        guard !scopes.isEmpty else {
            guard let floor = state.globalFloor else { return true }
            return level >= floor
        }
        return scopes.contains { scope in
            guard let floor = effectiveFloor(for: scope, state: state) else { return true }
            return level >= floor
        }
    }

    /// The nearest ancestor override, else the global floor. `nil` means
    /// no floor applies.
    private static func effectiveFloor(for scope: ScopeID, state: State) -> LogLevel? {
        var next: ScopeID? = scope
        while let id = next {
            if let floor = state.subtreeFloors[id] {
                return floor
            }
            next = state.scopes[id]?.parentID
        }
        return state.globalFloor
    }

    // MARK: LogRecorder

    public func defineScope(_ scope: LogScope) {
        let (isNew, journal) = state.withLock { state -> (Bool, LogJournal?) in
            guard state.scopes[scope.id] == nil else { return (false, nil) }
            state.scopes[scope.id] = scope
            state.pending.append(.scope(scope))
            return (true, state.journal)
        }
        guard isNew else { return }
        journal?.append(scope: scope)
        scheduleDrainIfNeeded()
    }

    public func record(_ original: LogRecord) {
        // Floor first: redaction must not run (touching PII) for records
        // the floor discards anyway. Floors apply to the record as emitted;
        // span lifecycle records carry their begin-time decision instead
        // (see `LogRecord.bypassesFloors`).
        if !original.bypassesFloors {
            guard shouldRecord(level: original.level, scopes: original.scopes) else {
                // A floored ambient event still moved the world: floors are
                // routing, not scrubbing, so the running snapshot folds the
                // state in even though the event itself isn't recorded —
                // otherwise every later record would carry a stale value.
                foldDiscardedAmbientState(of: original) { event, snapshot in
                    AmbientSnapshot.folding(event, into: snapshot)
                }
                return
            }
        }
        guard let admitted = redacted(original) else {
            // Suppression is content scrubbing: folding the value in would
            // smear exactly what the hook suppressed across every later
            // record's snapshot, and keeping the previous value would lie —
            // so the snapshot forgets the kind instead.
            foldDiscardedAmbientState(of: original) { event, snapshot in
                snapshot?.removing(event.kind)
            }
            return
        }
        // `buffer` returns the record as buffered — with its ambient state
        // stamped on — and that copy is what journals and reaches sinks,
        // so the durable and live views can't disagree about it.
        let (record, journaled) = state.withLock { state -> (LogRecord, (LogJournal, Int)?) in
            let buffered = Self.buffer(admitted, into: &state, configuration: configuration)
            return (buffered, Self.stampForJournal(&state))
        }
        // The file append happens outside the lock (I/O must not serialize
        // every emitter); the sequence stamped inside it restores buffer
        // order at replay.
        if let (journal, sequence) = journaled {
            journal.append(record, sequence: sequence)
        }
        scheduleFollowUp(for: record)
    }

    /// Reserve the next journal sequence, when a journal is installed —
    /// call under the state lock, append outside it.
    private static func stampForJournal(_ state: inout State) -> (LogJournal, Int)? {
        guard let journal = state.journal else { return nil }
        state.journalSequence += 1
        return (journal, state.journalSequence)
    }

    /// Stamp `record` with the ambient state, append it to the buffers, and
    /// yield it to live observers — the in-lock half of delivery, shared by
    /// ``record(_:)`` and ``beginSpan(key:span:began:)``. Returns the record
    /// as buffered, which is what callers must journal and deliver.
    ///
    /// Yields happen *inside* the lock so live streams see buffered order:
    /// yields only buffer (no consumer runs under us), and out-of-lock
    /// yields from racing emitters could invert — e.g. a span's end reaching
    /// an observer before its began.
    private static func buffer(
        _ record: LogRecord,
        into state: inout State,
        configuration: Configuration,
    ) -> LogRecord {
        let stamped = stamped(record, in: &state)
        append(stamped, to: &state, configuration: configuration)
        for observer in state.observers.values {
            observer.yield(stamped)
        }
        return stamped
    }

    /// Fold an ambient state change into the running snapshot, then stamp
    /// that snapshot onto the record.
    ///
    /// Folding *before* stamping is deliberate: an ambient event carries the
    /// state it announces, not the one it replaced, so an event and the
    /// snapshot attached to it can never disagree.
    private static func stamped(_ record: LogRecord, in state: inout State) -> LogRecord {
        if let event = record.event as? AmbientEvent {
            state.ambient = AmbientSnapshot.folding(event, into: state.ambient)
        }
        var stamped = record
        stamped.ambient = state.ambient
        return stamped
    }

    /// Update the running ambient snapshot for an ambient event the
    /// admission gates discarded. The record never reaches `buffer` (and so
    /// never `stamped(_:in:)`), but the state change it announced is still
    /// real — `fold` decides how it lands, since a floored event and a
    /// redaction-suppressed one warrant different treatment.
    private func foldDiscardedAmbientState(
        of record: LogRecord,
        _ fold: @Sendable (AmbientEvent, AmbientSnapshot?) -> AmbientSnapshot?,
    ) {
        guard let event = record.event as? AmbientEvent, event.reporting == .state else { return }
        state.withLock { state in
            state.ambient = fold(event, state.ambient)
        }
    }

    /// The outside-lock tail of delivery: kick the drain, and auto-flush
    /// for records at the flush threshold.
    private func scheduleFollowUp(for record: LogRecord) {
        scheduleDrainIfNeeded()
        if record.level >= configuration.flushThreshold {
            scheduleAutoFlush()
        }
    }

    /// Apply the configured redaction hook. Span pair records are
    /// *transform-only*: a hook may rewrite them, but `nil` (suppression)
    /// falls back to a stripped copy — a suppressed half would strand its
    /// partner (see `LogRecord.isProtectedFromDropping`), and level floors
    /// are the supported way to silence spans.
    private func redacted(_ record: LogRecord) -> LogRecord? {
        guard let redact = configuration.redact else { return record }
        if let transformed = redact(record) { return transformed }
        guard record.isProtectedFromDropping else { return nil }
        return record.strippedOfSensitivePayload()
    }

    /// Request an automatic flush, coalescing: one task flushes no matter
    /// how many qualifying records arrive (an error storm must not spawn a
    /// task per record), and records landing mid-flush get exactly one
    /// follow-up flush so their durability is still covered.
    private func scheduleAutoFlush() {
        state.withLock { state in
            guard state.autoFlushTask == nil else {
                state.autoFlushPending = true
                return
            }
            state.autoFlushTask = Task { await self.runAutoFlush() }
        }
    }

    private func runAutoFlush() async {
        while true {
            await flush()
            let runAgain = state.withLock { state -> Bool in
                if state.autoFlushPending {
                    state.autoFlushPending = false
                    return true
                }
                state.autoFlushTask = nil
                return false
            }
            guard runAgain else { return }
        }
    }

    /// Append to the recent buffer and pending queue, applying both bounds.
    private static func append(
        _ record: LogRecord,
        to state: inout State,
        configuration: Configuration,
    ) {
        state.recent.append(record)
        let recentOverflow = state.recent.count - configuration.recentBufferCapacity
        if recentOverflow > 0 {
            state.recent.removeFirst(recentOverflow)
        }

        state.pending.append(.record(record))
        state.pendingRecordCount += 1
        let pendingOverflow = state.pendingRecordCount - configuration.pendingBufferCapacity
        if pendingOverflow > 0 {
            var remainingToDrop = pendingOverflow
            state.pending.removeAll { item in
                guard remainingToDrop > 0,
                      case let .record(record) = item,
                      !record.isProtectedFromDropping
                else { return false }
                remainingToDrop -= 1
                return true
            }
            // Protected records (span pairs, like scope definitions) never
            // drop, so a queue saturated with them can exceed the bound —
            // they're rare and small, and a split pair is worse than a
            // briefly oversized queue.
            let dropped = pendingOverflow - remainingToDrop
            state.pendingRecordCount -= dropped
            state.droppedCount += dropped
        }
    }

    /// Resolve a scope the system has seen.
    public func scope(for id: ScopeID) -> LogScope? {
        state.withLock { $0.scopes[id] }
    }

    /// Keep an ambient source alive until stopped — see
    /// `startAmbientSource(_:)`.
    func retainAmbientSource(_ source: some AmbientEventSource) {
        state.withLock { $0.ambientSources.append(source) }
    }

    /// Release every retained ambient source, returning them so the caller
    /// can stop them — see `stopAmbientSources()`.
    func releaseAmbientSources() -> [any AmbientEventSource] {
        state.withLock { state in
            let sources = state.ambientSources
            state.ambientSources = []
            return sources
        }
    }

    /// The developer "log view mode" flag: when enabled, inspectable UI
    /// (PeriscopeTools' `logInspectable` modifier) reveals the events behind
    /// each wrapped view. This is the flag's source of truth — observable
    /// mirrors (PeriscopeTools' inspector) follow it via
    /// ``inspectModeChanges()``, so writing here or through a mirror
    /// converges either way.
    public var isInspectModeEnabled: Bool {
        get { state.withLock(\.inspectModeEnabled) }
        set {
            // Yield *inside* the lock: yields only buffer (no consumer runs
            // under us), and racing setters outside the lock could deliver
            // out of order — with bufferingNewest(1) a subscriber would
            // then hold the losing value forever.
            state.withLock { state in
                guard state.inspectModeEnabled != newValue else { return }
                state.inspectModeEnabled = newValue
                for observer in state.inspectObservers.values {
                    observer.yield(newValue)
                }
            }
        }
    }

    /// The inspect flag over time: the current value immediately, then one
    /// per change (redundant writes don't re-yield). Only the latest value
    /// buffers for a slow consumer. The observer is unregistered when the
    /// stream's consumer cancels.
    public func inspectModeChanges() -> AsyncStream<Bool> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            state.withLock { state in
                continuation.yield(state.inspectModeEnabled)
                state.inspectObservers[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { state in
                    state.inspectObservers[id] = nil
                }
            }
        }
    }

    // MARK: Open spans

    public func beginSpan(key: SpanKey, span: OpenSpan, began: LogRecord?) -> OpenSpan? {
        // Redact outside the lock, like `record(_:)` — the closure is user
        // code and may itself log, which would deadlock under our lock.
        // `redacted` never suppresses a protected began (transform-only),
        // so a floor-admitted pair stays whole through redaction too.
        let admitted = began.flatMap { redacted($0) }
        // One lock acquisition for registry + buffer: the span becomes
        // visible for closing only with its began already in the pipeline,
        // so no interleaving can record this span's end first.
        let (superseded, buffered, journaled) = state.withLock {
            state -> (OpenSpan?, LogRecord?, (LogJournal, Int)?) in
            let prior = state.openSpans.removeValue(forKey: key)
            state.openSpans[key] = span
            guard let admitted else { return (prior, nil, nil) }
            let stamped = Self.buffer(admitted, into: &state, configuration: configuration)
            return (prior, stamped, Self.stampForJournal(&state))
        }
        if let buffered {
            if let (journal, sequence) = journaled {
                journal.append(buffered, sequence: sequence)
            }
            scheduleFollowUp(for: buffered)
        }
        scheduleWatchdogIfNeeded()
        return superseded
    }

    public func closeSpan(key: SpanKey) -> OpenSpan? {
        state.withLock { $0.openSpans.removeValue(forKey: key) }
    }

    /// A snapshot of every span currently open via `begin(for:)`, longest
    /// running first — the data behind "what's in flight right now"
    /// developer surfaces.
    public func openSpans() -> [OpenSpan] {
        state.withLock { Array($0.openSpans.values) }
            .sorted { $0.start < $1.start }
    }

    /// Close every bounded open span whose budget has elapsed as of `now`,
    /// emitting its ``SpanEnded`` (`.expired`) with the begin-time context.
    /// The watchdog calls this at deadlines; tests call it directly with
    /// fabricated instants instead of sleeping.
    @_spi(Testing) public func sweepOverdueSpans(now: ContinuousClock.Instant) {
        let expired: [OpenSpan] = state.withLock { state in
            var overdue: [OpenSpan] = []
            for (key, span) in state.openSpans {
                guard case let .bounded(budget) = span.lifetime,
                      span.start + budget <= now
                else { continue }
                state.openSpans[key] = nil
                overdue.append(span)
            }
            return overdue
        }
        for span in expired {
            SpanSignposts.end(span.id)
            guard case let .bounded(budget) = span.lifetime else { continue }
            guard span.beganRecorded else { continue }
            var closing = LogRecord(
                date: Date(),
                event: SpanEnded(
                    spanID: span.id,
                    name: span.name,
                    duration: now - span.start,
                    exit: .expired(budget: budget),
                ),
                scopes: span.scopes,
                tags: span.tags,
            )
            closing.bypassesFloors = true
            record(closing)
        }
    }

    /// The earliest expiry among bounded open spans, if any.
    private static func earliestDeadline(in state: State) -> ContinuousClock.Instant? {
        state.openSpans.values.compactMap { span -> ContinuousClock.Instant? in
            guard case let .bounded(budget) = span.lifetime else { return nil }
            return span.start + budget
        }.min()
    }

    /// Ensure a watchdog task will wake at (or before) the earliest bounded
    /// deadline; respawn when a new span needs an earlier wake than the
    /// current sleep.
    private func scheduleWatchdogIfNeeded() {
        state.withLock { state in
            guard let next = Self.earliestDeadline(in: state) else { return }
            if state.watchdogTask != nil, let wakeAt = state.watchdogWakeAt, wakeAt <= next {
                return
            }
            state.watchdogTask?.cancel()
            state.watchdogGeneration += 1
            state.watchdogWakeAt = next
            let generation = state.watchdogGeneration
            // Weak self throughout: the watchdog may sleep for minutes, and
            // it must not keep a discarded system (test suites make many)
            // alive until its next wake. Strong promotion is per-call only,
            // never held across the sleep.
            state.watchdogTask = Task { [weak self] in
                while true {
                    guard let wakeAt = self?.nextWatchdogWake(generation: generation) else {
                        return
                    }
                    try? await Task.sleep(until: wakeAt, clock: .continuous)
                    if Task.isCancelled { return }
                    self?.sweepOverdueSpans(now: ContinuousClock().now)
                }
            }
        }
    }

    /// The watchdog's loop head: the next deadline to sleep until, or `nil`
    /// when this generation is stale or nothing bounded remains open (in
    /// which case the watchdog retires).
    private func nextWatchdogWake(generation: Int) -> ContinuousClock.Instant? {
        state.withLock { state in
            guard state.watchdogGeneration == generation else { return nil }
            guard let next = Self.earliestDeadline(in: state) else {
                state.watchdogTask = nil
                state.watchdogWakeAt = nil
                return nil
            }
            state.watchdogWakeAt = next
            return next
        }
    }

    // MARK: Live records

    /// The most recent records, oldest first (bounded by
    /// ``Configuration/recentBufferCapacity``).
    public func recentRecords() -> [LogRecord] {
        state.withLock(\.recent)
    }

    /// The number of currently registered ``liveRecords()`` observers —
    /// lets tests assert subscription lifecycles deterministically.
    @_spi(Testing) public var liveObserverCount: Int {
        state.withLock { $0.observers.count }
    }

    /// Every record emitted from now on, one at a time. The observer is
    /// unregistered automatically when the stream's consumer cancels.
    /// Buffering is bounded (``Configuration/liveBufferCapacity``): a
    /// consumer that falls behind loses the *oldest* buffered records —
    /// live surfaces want the newest activity, and the durable history is
    /// the store's job.
    public func liveRecords() -> AsyncStream<LogRecord> {
        let id = UUID()
        return AsyncStream(
            bufferingPolicy: .bufferingNewest(configuration.liveBufferCapacity),
        ) { continuation in
            state.withLock { state in
                state.observers[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { state in
                    state.observers[id] = nil
                }
            }
        }
    }

    // MARK: Draining

    /// Wait until everything pending has reached every sink, then ask each
    /// sink to persist its own buffers.
    public func flush() async {
        await drainInFlightWork()
        let sinks = state.withLock(\.sinks)
        for registered in sinks {
            await registered.sink.flush()
        }
    }

    /// Wait until no drain is in flight — every record queued before the call
    /// has reached every sink registered when its batch was taken.
    private func drainInFlightWork() async {
        while let task = state.withLock({ $0.drainTask }) {
            await task.value
        }
    }

    private func scheduleDrainIfNeeded() {
        state.withLock { state in
            guard state.drainTask == nil, !state.pending.isEmpty else { return }
            state.drainTask = Task { await self.drain() }
        }
    }

    private func drain() async {
        while true {
            let next: (
                items: [PendingItem],
                sinks: [RegisteredSink],
                dropReport: LogRecord?,
            )? = state.withLock { state in
                guard !state.pending.isEmpty else {
                    state.drainTask = nil
                    return nil
                }
                let items = state.pending
                state.pending.removeAll()
                state.pendingRecordCount = 0
                var dropReport: LogRecord?
                if state.droppedCount > 0 {
                    var report = LogRecord(
                        date: Date(),
                        event: DroppedEvents(count: state.droppedCount),
                        scopes: [systemScope.id],
                    )
                    // Stamped here rather than in `buffer`: the report is
                    // synthesized during the drain and never re-enters the
                    // pending queue, so it never passes through it.
                    report.ambient = state.ambient
                    dropReport = report
                    state.droppedCount = 0
                }
                return (items, state.sinks, dropReport)
            }
            guard var (items, sinks, dropReport) = next else { return }
            if let dropReport {
                announceDropReport(dropReport)
                // The gap sits at the front of the record backlog, so the
                // report slots before the surviving records — but after the
                // leading scope run, so a just-added sink has its replay
                // (including the system scope) before any record.
                let leadingScopes = items.prefix { item in
                    if case .scope = item { true } else { false }
                }
                items.insert(.record(dropReport), at: leadingScopes.count)
            }
            for chunk in Self.chunked(items) {
                for registered in sinks {
                    switch chunk {
                        case let .scopes(scopes): await registered.sink.defineScopes(scopes)
                        case let .records(records): await registered.sink.write(records)
                    }
                }
            }
        }
    }

    /// Surface a synthetic drop report in the recent buffer and live streams
    /// (it never re-enters the pending queue). Yields in-lock, like
    /// ``buffer(_:into:configuration:)``, so live order matches.
    private func announceDropReport(_ record: LogRecord) {
        state.withLock { state in
            state.recent.append(record)
            let overflow = state.recent.count - configuration.recentBufferCapacity
            if overflow > 0 {
                state.recent.removeFirst(overflow)
            }
            for observer in state.observers.values {
                observer.yield(record)
            }
        }
    }

    /// A run of consecutive same-kind pending items, ready for sink delivery.
    private enum Chunk {
        case scopes([LogScope])
        case records([LogRecord])
    }

    /// Group consecutive pending items so order is preserved while sinks
    /// still receive batches. Accumulates runs in mutable buffers — O(n),
    /// where rewriting the last chunk per item would copy it every
    /// iteration and go quadratic on large backlogs.
    private static func chunked(_ items: [PendingItem]) -> [Chunk] {
        var chunks: [Chunk] = []
        var scopeRun: [LogScope] = []
        var recordRun: [LogRecord] = []

        func closeScopeRun() {
            guard !scopeRun.isEmpty else { return }
            chunks.append(.scopes(scopeRun))
            scopeRun.removeAll()
        }

        func closeRecordRun() {
            guard !recordRun.isEmpty else { return }
            chunks.append(.records(recordRun))
            recordRun.removeAll()
        }

        for item in items {
            switch item {
                case let .scope(scope):
                    closeRecordRun()
                    scopeRun.append(scope)
                case let .record(record):
                    closeScopeRun()
                    recordRun.append(record)
            }
        }
        closeScopeRun()
        closeRecordRun()
        return chunks
    }
}

extension Log {
    /// A root logger recording into a Periscope system — `Log<MyRoot>()`
    /// logs through ``Periscope/shared``.
    public init(system: Periscope = .shared) {
        self.init(recorder: system)
    }
}
