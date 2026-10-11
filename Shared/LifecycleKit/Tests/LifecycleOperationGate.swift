/// Holds an operation through cancellation until the test releases its dependency.
@MainActor
final class LifecycleOperationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var entered = false
    private(set) var cancelled = false

    func wait() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation {
                continuation = $0
                entered = true
            }
        } onCancel: {
            Task { @MainActor in self.cancelled = true }
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
