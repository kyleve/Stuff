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

        /// Records at this level or above trigger an automatic ``flush()``,
        /// so the most important events don't sit in sink buffers when the
        /// process dies.
        public var flushThreshold: LogLevel

        /// Applied to every record before it is buffered or delivered.
        /// Return a transformed record to scrub PII, or `nil` to suppress
        /// the record entirely. `nil` hook means no redaction.
        public var redact: (@Sendable (LogRecord) -> LogRecord?)?

        public init(
            recentBufferCapacity: Int = 500,
            pendingBufferCapacity: Int = 5000,
            flushThreshold: LogLevel = .error,
            redact: (@Sendable (LogRecord) -> LogRecord?)? = nil,
        ) {
            self.recentBufferCapacity = recentBufferCapacity
            self.pendingBufferCapacity = pendingBufferCapacity
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
        /// The active drain task; `nil` exactly when nothing is draining.
        var drainTask: Task<Void, Never>?
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
        self.configuration = configuration
        state = OSAllocatedUnfairLock(initialState: State(sinks: sinks))
        defineScope(systemScope)
    }

    // MARK: Sinks

    /// Register a sink. All scopes defined so far are replayed to the
    /// pipeline so the new sink can resolve every record it will see.
    public func add(sink: some LogSink) {
        state.withLock { state in
            state.sinks.append(sink)
            state.pending.append(contentsOf: state.scopes.values.map(PendingItem.scope))
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
        let record: LogRecord
        if let redact = configuration.redact {
            guard let redacted = redact(original) else { return }
            record = redacted
        } else {
            record = original
        }
        let observers: [AsyncStream<LogRecord>.Continuation]? = state.withLock { state in
            guard Self.passesFloor(level: record.level, scopes: record.scopes, state: state)
            else { return nil }
            Self.append(record, to: &state, configuration: configuration)
            return Array(state.observers.values)
        }
        guard let observers else { return }
        for observer in observers {
            observer.yield(record)
        }
        scheduleDrainIfNeeded()
        if record.level >= configuration.flushThreshold {
            Task { await self.flush() }
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

    // MARK: Open spans

    public func openSpan(
        key: SpanKey,
        name: String,
        start: ContinuousClock.Instant,
    ) -> SpanID? {
        state.withLock { state in
            guard state.openSpans[key] == nil else { return nil }
            let span = OpenSpan(id: SpanID(), name: name, start: start)
            state.openSpans[key] = span
            return span.id
        }
    }

    public func closeSpan(key: SpanKey) -> OpenSpan? {
        state.withLock { $0.openSpans.removeValue(forKey: key) }
    }

    // MARK: Live records

    /// The most recent records, oldest first (bounded by
    /// ``Configuration/recentBufferCapacity``).
    public func recentRecords() -> [LogRecord] {
        state.withLock(\.recent)
    }

    /// Every record emitted from now on, one at a time. The observer is
    /// unregistered automatically when the stream's consumer cancels.
    public func liveRecords() -> AsyncStream<LogRecord> {
        let id = UUID()
        return AsyncStream { continuation in
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
            guard let (items, sinks, dropReport) = next else { return }
            if let dropReport {
                announceDropReport(dropReport)
                for sink in sinks {
                    await sink.write([dropReport])
                }
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
    /// still receive batches.
    private static func chunked(_ items: [PendingItem]) -> [Chunk] {
        var chunks: [Chunk] = []
        for item in items {
            switch (chunks.last, item) {
                case let (.scopes(scopes), .scope(scope)):
                    chunks[chunks.count - 1] = .scopes(scopes + [scope])
                case let (.records(records), .record(record)):
                    chunks[chunks.count - 1] = .records(records + [record])
                case let (_, .scope(scope)):
                    chunks.append(.scopes([scope]))
                case let (_, .record(record)):
                    chunks.append(.records([record]))
            }
        }
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
