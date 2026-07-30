/// Serializes expensive screen construction so the main actor can render between previews.
@MainActor
final class FlyoverContentLoadCoordinator {
    private var isLoading = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func perform(_ operation: @MainActor () async -> Void) async {
        await acquire()
        defer { release() }
        guard Task.isCancelled == false else {
            return
        }
        await Task.yield()
        guard Task.isCancelled == false else {
            return
        }
        await operation()
        await Task.yield()
    }

    private func acquire() async {
        guard isLoading else {
            isLoading = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        guard waiters.isEmpty == false else {
            isLoading = false
            return
        }
        waiters.removeFirst().resume()
    }
}
