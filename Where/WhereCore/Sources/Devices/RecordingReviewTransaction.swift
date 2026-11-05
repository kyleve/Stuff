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
        try await apply([record], reviewed: evidence)
    }

    func apply(
        _ records: [VersionedHistoryRecord],
        reviewed evidence: RecordingReviewEvidence,
    ) async throws -> Outcome {
        guard !records.isEmpty else { throw DataCompatibilityError.incompleteRecord }
        guard Set(records.map(\.id)).count == records.count
        else { throw DataCompatibilityError.conflictingRecord }
        for attempt in 0 ..< Self.maximumAttempts {
            do {
                return try await store.perform(expectedDataGenerationID: evidence.generationID) {
                    let controls = try await RecordingControlStore(store: store, policy: policy)
                        .snapshot()
                    let committed = Dictionary(uniqueKeysWithValues: controls.records.map {
                        ($0.id, $0)
                    })
                    for record in records {
                        if let saved = committed[record.id], saved != record {
                            throw DataCompatibilityError.conflictingRecord
                        }
                    }
                    if records.allSatisfy({ committed[$0.id] != nil }) {
                        return Outcome.applied
                    }
                    // A partially delivered batch is evidence of a changed snapshot. Do not
                    // append its missing controls without another complete user review.
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
                        records,
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
