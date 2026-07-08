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

        public init(recentBufferCapacity: Int = 500) {
            self.recentBufferCapacity = recentBufferCapacity
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
        var recent: [LogRecord] = []
        var observers: [UUID: AsyncStream<LogRecord>.Continuation] = [:]
        /// The active drain task; `nil` exactly when nothing is draining.
        var drainTask: Task<Void, Never>?
    }

    public let configuration: Configuration
    private let state: OSAllocatedUnfairLock<State>

    public init(configuration: Configuration, sinks: [any LogSink]) {
        precondition(
            configuration.recentBufferCapacity > 0,
            "recentBufferCapacity must be positive",
        )
        self.configuration = configuration
        state = OSAllocatedUnfairLock(initialState: State(sinks: sinks))
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

    public func record(_ record: LogRecord) {
        let observers = state.withLock { state in
            state.recent.append(record)
            let overflow = state.recent.count - configuration.recentBufferCapacity
            if overflow > 0 {
                state.recent.removeFirst(overflow)
            }
            state.pending.append(.record(record))
            return Array(state.observers.values)
        }
        for observer in observers {
            observer.yield(record)
        }
        scheduleDrainIfNeeded()
    }

    /// Resolve a scope the system has seen.
    public func scope(for id: ScopeID) -> LogScope? {
        state.withLock { $0.scopes[id] }
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
            let next: (items: [PendingItem], sinks: [any LogSink])? = state.withLock { state in
                guard !state.pending.isEmpty else {
                    state.drainTask = nil
                    return nil
                }
                let items = state.pending
                state.pending.removeAll()
                return (items, state.sinks)
            }
            guard let (items, sinks) = next else { return }
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
