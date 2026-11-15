import Foundation

/// Serializes expensive screen construction and releases cancelled queued requests promptly.
@MainActor
final class FlyoverContentLoadCoordinator {
    private struct Waiter {
        struct ID: Hashable {
            let rawValue = UUID()
        }

        let id: ID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var isLoading = false
    private var waiters: [Waiter] = []

    func perform(_ operation: @MainActor () async -> Void) async {
        guard await acquire() else {
            return
        }
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

    private func acquire() async -> Bool {
        guard Task.isCancelled == false else {
            return false
        }
        guard isLoading else {
            isLoading = true
            return true
        }
        let waiterID = Waiter.ID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard Task.isCancelled == false else {
                    continuation.resume(returning: false)
                    return
                }
                waiters.append(Waiter(id: waiterID, continuation: continuation))
            }
        } onCancel: {
            Task { @MainActor in
                self.cancel(waiterID)
            }
        }
    }

    private func cancel(_ waiterID: Waiter.ID) {
        guard let index = waiters.firstIndex(where: { $0.id == waiterID }) else {
            return
        }
        waiters.remove(at: index).continuation.resume(returning: false)
    }

    private func release() {
        guard waiters.isEmpty == false else {
            isLoading = false
            return
        }
        waiters.removeFirst().continuation.resume(returning: true)
    }
}
