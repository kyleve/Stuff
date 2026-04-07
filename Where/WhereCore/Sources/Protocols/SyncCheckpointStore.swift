public protocol SyncCheckpointStore: Sendable {
    func checkpoint() async -> SyncCheckpoint
    func save(_ checkpoint: SyncCheckpoint) async
    func reset() async
}
