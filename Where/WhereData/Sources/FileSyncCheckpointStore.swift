import Foundation
import WhereCore

public actor FileSyncCheckpointStore: SyncCheckpointStore {
    private let store: JSONFileStore<SyncCheckpoint>

    public init(fileURL: URL) {
        store = JSONFileStore(fileURL: fileURL)
    }

    public func checkpoint() async -> SyncCheckpoint {
        store.load(defaultValue: .init(state: .idle))
    }

    public func save(_ checkpoint: SyncCheckpoint) async {
        store.save(checkpoint)
    }

    public func reset() async {
        store.save(.init(state: .idle))
    }
}
