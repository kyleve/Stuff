import Foundation
import os

/// A thread-safe, bounded in-memory ring buffer of ``LogEntry`` values, shared
/// between the logging facade (which records into it from any thread/actor) and
/// the viewer (which reads snapshots and observes changes on the main actor).
///
/// Recording never hops to the main actor: state is guarded by an
/// `OSAllocatedUnfairLock`, and observers are notified through `AsyncStream`s
/// that carry a fresh snapshot. Once `capacity` is reached the oldest entries
/// are evicted.
public final class LogStore: Sendable {
    private struct State {
        var entries: [LogEntry] = []
        var observers: [UUID: AsyncStream<[LogEntry]>.Continuation] = [:]
    }

    /// Maximum number of entries retained; older entries are dropped past this.
    public let capacity: Int

    private let state: OSAllocatedUnfairLock<State>

    public init(capacity: Int = 1000) {
        precondition(capacity > 0, "LogStore capacity must be positive")
        self.capacity = capacity
        state = OSAllocatedUnfairLock(initialState: State())
    }

    /// Append an entry, evicting the oldest if at capacity, and notify observers.
    public func record(_ entry: LogEntry) {
        let (snapshot, observers) = state.withLock { state -> (
            [LogEntry],
            [AsyncStream<[LogEntry]>.Continuation]
        ) in
            state.entries.append(entry)
            let overflow = state.entries.count - capacity
            if overflow > 0 {
                state.entries.removeFirst(overflow)
            }
            return (state.entries, Array(state.observers.values))
        }
        for observer in observers {
            observer.yield(snapshot)
        }
    }

    /// The current entries, oldest first.
    public func snapshot() -> [LogEntry] {
        state.withLock { $0.entries }
    }

    /// Drop all buffered entries and notify observers with the empty snapshot.
    public func clear() {
        let observers = state.withLock { state -> [AsyncStream<[LogEntry]>.Continuation] in
            state.entries.removeAll(keepingCapacity: true)
            return Array(state.observers.values)
        }
        for observer in observers {
            observer.yield([])
        }
    }

    /// An async sequence of snapshots: yields the current buffer immediately,
    /// then a fresh snapshot on every `record`/`clear`. The observer is
    /// unregistered automatically when the stream's consumer cancels.
    public func changes() -> AsyncStream<[LogEntry]> {
        let id = UUID()
        return AsyncStream<[LogEntry]> { continuation in
            let initial = state.withLock { state -> [LogEntry] in
                state.observers[id] = continuation
                return state.entries
            }
            continuation.yield(initial)
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { state in
                    state.observers[id] = nil
                }
            }
        }
    }
}
