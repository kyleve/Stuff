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
            options: [],
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
