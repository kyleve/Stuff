/// Value-based control access over the caller's admitted store. Reviewed writes keep this
/// collaborator inside their outer generation-guarded transaction and pinned read snapshot.
public struct RecordingControlStore: Sendable {
    private let store: any WhereStore
    private let policy: DataCompatibilityPolicy

    public init(store: any WhereStore, policy: DataCompatibilityPolicy) {
        self.store = store
        self.policy = policy
    }

    public func snapshot() async throws -> RecordingControlSnapshot {
        try await store.readSnapshot {
            try await RecordingControlSnapshot(
                records: store.versionedHistoryRecords(policy: policy),
                generationID: store.dataGeneration().id,
                policy: policy,
            )
        }
    }

    /// Append prepared immutable bytes. The caller owns the transaction and post-commit fan-out.
    /// This method allocates no operation identity and never adds unreviewed predecessors.
    func append(
        _ records: [VersionedHistoryRecord],
        expectedGenerationID: WhereDataGenerationID,
    ) async throws {
        try await store.perform(expectedDataGenerationID: expectedGenerationID) {
            let current = try await snapshot()
            guard current.generationID == expectedGenerationID
            else { throw RecordingPersistenceError.dataGenerationChanged }
            _ = try RecordingControlSnapshot(
                records: current.records + records,
                generationID: expectedGenerationID,
                policy: policy,
            )
            for record in records {
                try await store.addVersionedHistoryRecord(record)
            }
        }
    }
}
