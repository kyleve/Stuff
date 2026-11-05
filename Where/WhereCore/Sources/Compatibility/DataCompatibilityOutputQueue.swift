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

    @discardableResult
    func publish<Output: Sendable>(
        _ operation: @escaping @Sendable () async -> Output,
    ) async -> Output? {
        guard case let .active(previous) = state else { return nil }
        let access = access
        // Own this task until it completes even if its caller is cancelled. The system may
        // already have accepted the operation, so cancellation is not a withdrawal barrier.
        let task = Task<Output?, Never> {
            await previous?.value
            guard !access.isRevoked else { return nil }
            return await operation()
        }
        let completion = Task { _ = await task.value }
        state = .active(tail: completion)
        return await task.value
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
