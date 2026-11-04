/// Serializes asynchronous output with its terminal withdrawal. Cancellation cannot abandon a
/// system operation already submitted; retirement drains it before removing the owned output.
actor DataCompatibilityOutputQueue {
    private enum State {
        case active(tail: Task<Void, Never>?)
        case retired(withdrawal: Task<Void, Never>)
    }

    private let access: DataCompatibilityAccess
    private var state: State = .active(tail: nil)

    init(access: DataCompatibilityAccess) {
        self.access = access
    }

    func publish(_ operation: @escaping @Sendable () async -> Void) async {
        guard case let .active(previous) = state else { return }
        let access = access
        // Own this task until it completes even if its caller is cancelled. The system may
        // already have accepted the operation, so cancellation is not a withdrawal barrier.
        let task = Task {
            await previous?.value
            guard !access.isRevoked else { return }
            await operation()
        }
        state = .active(tail: task)
        await task.value
    }

    func retire(withdraw: @escaping @Sendable () async -> Void) async {
        switch state {
            case let .retired(withdrawal):
                await withdrawal.value
            case let .active(previous):
                access.revoke()
                let task = Task {
                    await previous?.value
                    await withdraw()
                }
                state = .retired(withdrawal: task)
                await task.value
        }
    }
}
