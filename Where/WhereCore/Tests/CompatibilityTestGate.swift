import Foundation
import Synchronization

/// A condition-driven gate for suspended compatibility operations.
final class CompatibilityTestGate: Sendable {
    struct Channel {
        let stream: AsyncStream<Void>
        let continuation: AsyncStream<Void>.Continuation

        init() {
            (stream, continuation) = AsyncStream<Void>
                .makeStream(bufferingPolicy: .bufferingNewest(1))
        }
    }

    let entered = Channel()
    private enum State { case idle, waiting(CheckedContinuation<Void, Never>), released }
    private let state = Mutex(State.idle)

    func suspend() async {
        await withCheckedContinuation { continuation in
            state.withLock { state in
                switch state {
                    case .idle: state = .waiting(continuation)
                    case .released: continuation.resume()
                    case .waiting: preconditionFailure("Only one held operation per gate")
                }
            }
            entered.continuation.yield()
        }
    }

    func waitUntilEntered() async {
        for await _ in entered.stream {
            break
        }
    }

    func resume() {
        state.withLock { state in
            if case let .waiting(continuation) = state { continuation.resume() }
            state = .released
        }
    }
}
