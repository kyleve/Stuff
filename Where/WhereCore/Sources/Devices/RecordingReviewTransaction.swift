/// The shared commit protocol for reviewed recording controls. Callers bind their proposal to
/// an admitted service, then use this operation to preserve its evidence and immutable bytes.
struct RecordingReviewTransaction {
    enum Outcome {
        case applied
        case changed(RecordingReviewEvidence)
    }

    /// Continuous imports must not spin forever. A busy store leaves the original proposal
    /// intact so the user can retry it; no restart allocates another operation identity.
    private static let maximumAttempts = 3
    let store: any WhereStore
    let policy: DataCompatibilityPolicy

    #if DEBUG
        var beforeWrite: (@Sendable () async -> Void)?
    #endif

    func apply(
        _ record: VersionedHistoryRecord,
        reviewed evidence: RecordingReviewEvidence,
    ) async throws -> Outcome {
        for attempt in 0 ..< Self.maximumAttempts {
            do {
                return try await store.perform(expectedDataGenerationID: evidence.generationID) {
                    let controls = try await RecordingControlStore(store: store, policy: policy)
                        .snapshot()
                    if let committed = controls.records.first(where: { $0.id == record.id }) {
                        guard committed == record
                        else { throw DataCompatibilityError.conflictingRecord }
                        return Outcome.applied
                    }
                    let current = try await RecordingReviewReader(store: store, policy: policy)
                        .evidence(for: evidence.query)
                    guard current == evidence,
                          evidence.policyVersion == RecordingEvidencePolicy.version
                    else {
                        return Outcome.changed(current)
                    }
                    #if DEBUG
                        await beforeWrite?()
                    #endif
                    try await RecordingControlStore(store: store, policy: policy).append(
                        [record],
                        expectedGenerationID: evidence.generationID,
                    )
                    return Outcome.applied
                }
            } catch WhereStoreReadConflictError.changedDuringTransaction {
                if attempt + 1 == Self
                    .maximumAttempts { throw WhereStoreReadConflictError.changedDuringTransaction }
            }
        }
        preconditionFailure("The final save attempt must return or throw.")
    }
}
