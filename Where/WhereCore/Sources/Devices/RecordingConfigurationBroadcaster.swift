import Foundation

/// Fans applied current-installation recording state to independent coordinator subscribers.
///
/// The controller publishes only after its target-owned check-in commits. Presentation can
/// therefore mirror physical GPS state without observing every unrelated store transaction or
/// independently re-running the domain reconciliation policy.
final class RecordingConfigurationBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var subscribers:
        [UUID: AsyncStream<RecordingDeviceRuntimeUpdate>.Continuation] = [:]

    func send(_ update: RecordingDeviceRuntimeUpdate) {
        let continuations = lock.withLock { Array(subscribers.values) }
        for continuation in continuations {
            continuation.yield(update)
        }
    }

    func subscribe() -> AsyncStream<RecordingDeviceRuntimeUpdate> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: RecordingDeviceRuntimeUpdate.self,
            bufferingPolicy: .bufferingNewest(1),
        )
        lock.withLock { subscribers[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            lock.withLock { _ = subscribers.removeValue(forKey: id) }
        }
        return stream
    }

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
