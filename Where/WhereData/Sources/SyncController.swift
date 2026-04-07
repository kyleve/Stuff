import Foundation
import WhereCore

public actor SyncController {
    private let store: any SyncCheckpointStore

    public init(store: any SyncCheckpointStore) {
        self.store = store
    }

    public func checkpoint() async -> SyncCheckpoint {
        await store.checkpoint()
    }

    public func markSyncStarted(at date: Date = Date()) async {
        let current = await store.checkpoint()
        await store.save(
            SyncCheckpoint(
                state: .syncing,
                lastSuccessfulSyncAt: current.lastSuccessfulSyncAt,
                lastAttemptAt: date,
                failureReason: nil,
            ),
        )
    }

    public func markSyncSucceeded(at date: Date = Date()) async {
        await store.save(
            SyncCheckpoint(
                state: .idle,
                lastSuccessfulSyncAt: date,
                lastAttemptAt: date,
                failureReason: nil,
            ),
        )
    }

    public func markSyncFailed(reason: String, at date: Date = Date()) async {
        let current = await store.checkpoint()
        await store.save(
            SyncCheckpoint(
                state: .failed,
                lastSuccessfulSyncAt: current.lastSuccessfulSyncAt,
                lastAttemptAt: date,
                failureReason: reason,
            ),
        )
    }

    public func markPendingUpload() async {
        let current = await store.checkpoint()
        await store.save(
            SyncCheckpoint(
                state: .pendingUpload,
                lastSuccessfulSyncAt: current.lastSuccessfulSyncAt,
                lastAttemptAt: current.lastAttemptAt,
                failureReason: nil,
            ),
        )
    }
}
