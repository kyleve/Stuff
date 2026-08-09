import Foundation

/// Rebuilds headless derived outputs after a CloudKit or sibling-process import.
///
/// Local writers await their focused reconciliation inline; remote imports have no caller in this
/// process, so they need one long-lived observer. The source stream buffers only its newest event,
/// which coalesces a burst of imported transactions while a rebuild is already running.
final class RemoteDataChangeReconciler: @unchecked Sendable {
    private let task: Task<Void, Never>

    init(
        changes: AsyncStream<Void>,
        reconcile: @escaping @Sendable () async -> Void,
    ) {
        task = Task {
            for await _ in changes {
                guard !Task.isCancelled else { break }
                await reconcile()
            }
        }
    }

    deinit {
        task.cancel()
    }
}
