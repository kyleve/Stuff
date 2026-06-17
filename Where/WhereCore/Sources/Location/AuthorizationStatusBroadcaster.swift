import Foundation

/// Fans authorization-status changes out to any number of independent
/// `AsyncStream` subscribers.
///
/// A `LocationSource` produces a single sequence of status changes, but each
/// consumer needs its own stream: an `AsyncStream` is single-pass, so sharing
/// one continuation across consumers means a second subscriber sees nothing,
/// and cancelling one subscriber's iteration finishes the stream for *everyone*.
/// That breaks the app's `WhereSession`, which is dropped and rebuilt on reset
/// (each session subscribes afresh). This broadcaster hands every `subscribe()`
/// an isolated stream and drops its continuation when the consumer stops
/// iterating, so sessions never fight over — or tear down — each other's stream.
final class AuthorizationStatusBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var subscribers: [UUID: AsyncStream<LocationAuthorizationStatus>.Continuation] = [:]

    init() {}

    /// Deliver `status` to every current subscriber. A no-op for any subscriber
    /// whose consumer has already stopped iterating.
    func send(_ status: LocationAuthorizationStatus) {
        let continuations = lock.withLock { Array(subscribers.values) }
        for continuation in continuations {
            continuation.yield(status)
        }
    }

    /// A fresh, independent stream of subsequent status changes. Keeps only the
    /// newest pending value (matching CoreLocation's "latest wins" semantics)
    /// and removes itself from the fan-out when the consumer stops iterating
    /// (cancellation, `break`, or deinit of the iterating task).
    func subscribe() -> AsyncStream<LocationAuthorizationStatus> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            lock.withLock { subscribers[id] = continuation }
            // Assigned outside the `withLock` above: if the stream is already
            // terminated, this fires synchronously, and `NSLock` isn't
            // reentrant.
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                lock.withLock { _ = subscribers.removeValue(forKey: id) }
            }
        }
    }

    /// Finish every subscriber's stream. Used by test doubles tearing down.
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
