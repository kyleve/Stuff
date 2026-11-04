/// Holds one async operation at a known suspension boundary without a timing assumption.
actor CompatibilityTestGate {
    private enum State {
        case idle
        case waiting(CheckedContinuation<Void, Never>)
        case released
    }

    private var state: State = .idle
    private let entered: AsyncStream<Void>
    private let enteredContinuation: AsyncStream<Void>.Continuation

    init() {
        (entered, enteredContinuation) = AsyncStream
            .makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func suspend() async {
        await withCheckedContinuation { continuation in
            switch state {
                case .idle:
                    state = .waiting(continuation)
                    enteredContinuation.yield()
                    enteredContinuation.finish()
                case .released: continuation.resume()
                case .waiting: preconditionFailure("Only one operation can wait on this gate.")
            }
        }
    }

    func waitUntilEntered() async {
        for await _ in entered {
            break
        }
    }

    func resume() {
        if case let .waiting(continuation) = state { continuation.resume() }
        state = .released
    }
}
