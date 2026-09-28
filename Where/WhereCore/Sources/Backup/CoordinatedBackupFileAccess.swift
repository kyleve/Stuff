import Foundation
import os

/// Coordinates individual archive accesses, always using the URL supplied by
/// the coordinator. Directory coordination alone does not protect child data.
enum CoordinatedBackupFileAccess {
    /// Only cancel() crosses threads; Apple explicitly permits that operation.
    /// All other coordinator access stays on the synchronous caller's thread.
    /// https://developer.apple.com/documentation/foundation/nsfilecoordinator/cancel()
    private struct CancellationHandle: @unchecked Sendable {
        private let coordinator: NSFileCoordinator

        init(_ coordinator: NSFileCoordinator) {
            self.coordinator = coordinator
        }

        func cancel() {
            coordinator.cancel()
        }
    }

    static func read<Value: Sendable>(
        at url: URL,
        operation: (URL) throws -> Value,
    ) throws -> Value {
        try read(at: url, options: [], operation: operation)
    }

    static func read<Value: Sendable>(
        at url: URL,
        options: NSFileCoordinator.ReadingOptions,
        operation: (URL) throws -> Value,
    ) throws -> Value {
        let result = OSAllocatedUnfairLock<Result<Value, Error>?>(uncheckedState: nil)
        var error: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        let cancellation = CancellationHandle(coordinator)
        let progress = BackupService.cancellationProgress
        progress?.cancellationHandler = { cancellation.cancel() }
        defer { progress?.cancellationHandler = nil }
        try Task.checkCancellation()
        coordinator.coordinate(
            readingItemAt: url,
            options: options,
            error: &error,
        ) { coordinatedURL in
            let value = Result { try operation(coordinatedURL) }
            result.withLock { $0 = value }
        }
        if let error { throw error }
        guard let value = result.withLock({ $0 }) else {
            try Task.checkCancellation()
            preconditionFailure("File coordination did not execute its accessor.")
        }
        return try value.get()
    }

    /// Acquire all keeper reads and the candidate deletion together. Nested
    /// coordinators can deadlock and directory claims do not protect children.
    static func delete(
        at url: URL,
        keeping keeperURLs: [URL],
        operation: @escaping @Sendable (URL, [URL], Progress) throws -> Void,
    ) async throws {
        let candidate = NSFileAccessIntent.writingIntent(with: url, options: .forDeleting)
        let keepers = keeperURLs.map { NSFileAccessIntent.readingIntent(with: $0, options: []) }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        let cancellation = CancellationHandle(coordinator)
        let progress = Progress(totalUnitCount: 1)
        // The accessor runs outside the Swift task; pass its cancellation flag
        // explicitly and retain the coordinator until the callback has drained.
        defer { withExtendedLifetime(coordinator) {} }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<
                Void,
                Error
            >) in
                coordinator
                    .coordinate(with: keepers + [candidate], queue: OperationQueue()) { error in
                        let result = Result {
                            if progress.isCancelled { throw CancellationError() }
                            if let error { throw error }
                            try operation(candidate.url, keepers.map(\.url), progress)
                        }
                        continuation.resume(with: result)
                    }
            }
        } onCancel: {
            progress.cancel()
            cancellation.cancel()
        }
    }

    static func write<Value: Sendable>(
        at url: URL,
        options: NSFileCoordinator.WritingOptions,
        operation: (URL) throws -> Value,
    ) throws -> Value {
        let result = OSAllocatedUnfairLock<Result<Value, Error>?>(uncheckedState: nil)
        var error: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        let cancellation = CancellationHandle(coordinator)
        let progress = BackupService.cancellationProgress
        progress?.cancellationHandler = { cancellation.cancel() }
        defer { progress?.cancellationHandler = nil }
        try Task.checkCancellation()
        coordinator.coordinate(
            writingItemAt: url,
            options: options,
            error: &error,
        ) { coordinatedURL in
            let value = Result { try operation(coordinatedURL) }
            result.withLock { $0 = value }
        }
        if let error { throw error }
        guard let value = result.withLock({ $0 }) else {
            try Task.checkCancellation()
            preconditionFailure("File coordination did not execute its accessor.")
        }
        return try value.get()
    }
}
