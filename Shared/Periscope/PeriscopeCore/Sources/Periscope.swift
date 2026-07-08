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
///   drop and a synthetic ``DroppedEvents`` record marks the gap.
/// - **Redaction** — ``Configuration/redact`` transforms (or suppresses)
///   every record before it is buffered or delivered anywhere.
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
        /// drop (scope definitions never drop) and a ``DroppedEvents``
        /// record reports the gap.
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
        var sinks: [any LogSink] = []
        var pending: [PendingItem] = []
        var pendingRecordCount = 0
        var droppedCount = 0
        var recent: [LogRecord] = []
        var observers: [UUID: AsyncStream<LogRecord>.Continuation] = [:]
        var globalFloor: LogLevel?
        var subtreeFloors: [ScopeID: LogLevel] = [:]
        var openSpans: [SpanKey: OpenSpan] = [:]
        var ambientSources: [any AmbientEventSource] = []
        var inspectModeEnabled = false
        var inspectObservers: [UUID: AsyncStream<Bool>.Continuation] = [:]
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
        state = OSAllocatedUnfairLock(initialState: State(sinks: sinks))
        defineScope(systemScope)
    }

    // MARK: Sinks

    /// Register a sink. All scopes defined so far are replayed to the
    /// pipeline so the new sink can resolve every record it will see. The
    /// replay is *prepended*: records already pending must not reach the
    /// new sink ahead of the scopes they reference (existing sinks see the
    /// definitions again — idempotence is part of the sink contract).
    public func add(sink: some LogSink) {
        state.withLock { state in
            state.sinks.append(sink)
            state.pending.insert(
                contentsOf: state.scopes.values.map(PendingItem.scope),
                at: 0,
            )
        }
        scheduleDrainIfNeeded()
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
        let isNew = state.withLock { state in
            guard state.scopes[scope.id] == nil else { return false }
            state.scopes[scope.id] = scope
            state.pending.append(.scope(scope))
            return true
        }
        guard isNew else { return }
        scheduleDrainIfNeeded()
    }

    public func record(_ original: LogRecord) {
        // Floor first: redaction must not run (touching PII) for records
        // the floor discards anyway. Floors apply to the record as emitted;
        // span lifecycle records carry their begin-time decision instead
        // (see `LogRecord.bypassesFloors`).
        if !original.bypassesFloors {
            guard shouldRecord(level: original.level, scopes: original.scopes) else { return }
        }
        let record: LogRecord
        if let redact = configuration.redact {
            guard let redacted = redact(original) else { return }
            record = redacted
        } else {
            record = original
        }
        let observers = state.withLock { state in
            Self.append(record, to: &state, configuration: configuration)
            return Array(state.observers.values)
        }
        for observer in observers {
            observer.yield(record)
        }
        scheduleDrainIfNeeded()
        if record.level >= configuration.flushThreshold {
            scheduleAutoFlush()
        }
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
                guard remainingToDrop > 0, case .record = item else { return false }
                remainingToDrop -= 1
                return true
            }
            state.pendingRecordCount -= pendingOverflow
            state.droppedCount += pendingOverflow
        }
    }

    /// Resolve a scope the system has seen.
    public func scope(for id: ScopeID) -> LogScope? {
        state.withLock { $0.scopes[id] }
    }

    /// Keep an ambient source alive for the process lifetime — see
    /// `startAmbientSource(_:)`.
    func retainAmbientSource(_ source: some AmbientEventSource) {
        state.withLock { $0.ambientSources.append(source) }
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

    public func openSpan(key: SpanKey, span: OpenSpan) -> OpenSpan? {
        let superseded = state.withLock { state in
            let prior = state.openSpans.removeValue(forKey: key)
            state.openSpans[key] = span
            return prior
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
        while let task = state.withLock({ $0.drainTask }) {
            await task.value
        }
        let sinks = state.withLock(\.sinks)
        for sink in sinks {
            await sink.flush()
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
                sinks: [any LogSink],
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
                    dropReport = LogRecord(
                        date: Date(),
                        event: DroppedEvents(count: state.droppedCount),
                        scopes: [systemScope.id],
                    )
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
                for sink in sinks {
                    switch chunk {
                        case let .scopes(scopes): await sink.defineScopes(scopes)
                        case let .records(records): await sink.write(records)
                    }
                }
            }
        }
    }

    /// Surface a synthetic drop report in the recent buffer and live streams
    /// (it never re-enters the pending queue).
    private func announceDropReport(_ record: LogRecord) {
        let observers = state.withLock { state in
            state.recent.append(record)
            let overflow = state.recent.count - configuration.recentBufferCapacity
            if overflow > 0 {
                state.recent.removeFirst(overflow)
            }
            return Array(state.observers.values)
        }
        for observer in observers {
            observer.yield(record)
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
