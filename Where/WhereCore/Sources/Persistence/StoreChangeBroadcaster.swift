import Foundation

/// Fans "the persisted data changed" pings out to any number of independent
/// `AsyncStream` subscribers.
///
/// `SwiftDataStore` owns one for every committed change and another for the
/// remote-import subset. Consumers re-derive what they mirror, so the payload
/// is a bare `Void` — N pending pings and one are equivalent.
///
/// Like `AuthorizationStatusBroadcaster`, each `subscribe()` gets an isolated
/// stream — an `AsyncStream` is single-pass, and the session is dropped + rebuilt
/// on reset, so a shared stream would let one subscriber starve or tear down
/// another — and a subscriber drops out of the fan-out when its consumer stops
/// iterating.
final class StoreChangeBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var subscribers: [UUID: AsyncStream<Void>.Continuation] = [:]

    init() {}

    /// Ping every current subscriber. A no-op for any subscriber whose consumer
    /// has already stopped iterating.
    func send() {
        let continuations = lock.withLock { Array(subscribers.values) }
        for continuation in continuations {
            continuation.yield(())
        }
    }

    /// A fresh, independent stream of subsequent change pings. Coalesces to a
    /// single pending ping — the consumer re-reads the whole store, so N pending
    /// pings and one are equivalent — and removes itself from the fan-out when
    /// the consumer stops iterating (cancellation, `break`, or deinit of the
    /// iterating task).
    func subscribe() -> AsyncStream<Void> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            lock.withLock { subscribers[id] = continuation }
            // Assigned outside the `withLock` above: if the stream is already
            // terminated, this fires synchronously, and `NSLock` isn't reentrant.
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                lock.withLock { _ = subscribers.removeValue(forKey: id) }
            }
        }
    }

    /// Finish every subscriber's stream. Used by tests tearing down.
    func finishAll() {
        let continuations = lock.withLock {
            let values = Array(subscribers.values)
            subscribers.removeAll()
            return values
        }
        for continuation in continuations {
            continuation.finish()
        }
    }
}
