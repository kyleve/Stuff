import Foundation

/// Saves the exact reviewed source operation in a generation-guarded transaction. Unrelated
/// imports can retry that operation, but changed evidence never adopts new causal predecessors.
public struct RecordingChoiceCoordinator: Sendable {
    /// A preview belongs to the admitted service instance that created it. Fresh accounts can
    /// share the implicit initial generation, so a generation ID alone cannot bind that scope.
    struct ScopeID: Hashable { let rawValue: UUID }

    public enum ApplyResult: Hashable, Sendable {
        case applied
        case stale(RecordingChoiceReview)
    }

    private static let logger = WhereLog.reporting(RecordingChoiceCoordinatorLog.self)
    /// Bound automatic transaction restarts under continuous imports. A busy store surfaces its
    /// read-conflict error; the caller can retry the same proposal without allocating another ID.
    private static let maximumSaveAttempts = 3
    private let store: any WhereStore
    private let policy: DataCompatibilityPolicy
    private let author: RecordingDeviceID
    private let onCommitted: @Sendable () async -> Void
    private let scopeID = ScopeID(rawValue: UUID())

    #if DEBUG
        private var beforeWrite: (@Sendable () async -> Void)?

        @_spi(Testing) public mutating func setBeforeWriteForTesting(
            _ operation: @escaping @Sendable () async -> Void,
        ) {
            beforeWrite = operation
        }
    #endif

    public init(
        store: any WhereStore,
        policy: DataCompatibilityPolicy,
        author: RecordingDeviceID,
        onCommitted: @escaping @Sendable () async -> Void,
    ) {
        self.store = store
        self.policy = policy
        self.author = author
        self.onCommitted = onCommitted
    }

    public func review(_ request: RecordingChoiceRequest) async throws -> RecordingChoiceReview {
        try await Self.logger.measure(.review, budget: .seconds(2)) {
            try await store.readSnapshot {
                let state = try await store.dataCompatibilityState()
                try state.validate(policy: policy)
                guard state.requiredMajor == RecordingEvidencePolicy.version.major,
                      policy.current == RecordingEvidencePolicy.version
                else {
                    throw DataCompatibilityError.activationNotReady
                }
                let evidence = try await RecordingReviewReader(store: store, policy: policy)
                    .evidence(for: request)
                return try makeReview(request, evidence: evidence)
            }
        }
    }

    private func makeReview(
        _ request: RecordingChoiceRequest,
        evidence: RecordingReviewEvidence,
    ) throws -> RecordingChoiceReview {
        let periods: [RecordingPeriod]
        let scope: HistoryDecision.Scope
        switch request.scope {
            case .periods:
                periods = try request.searchPeriods()
                scope = .fixedPeriods
            case let .recordingDay(deviceID, day):
                let search = try RecordingDayCoverage.searchPeriod(for: day)
                let segments = try RecordingCalendarResolver.resolve(
                    evidence.controls.calendarContexts,
                    for: deviceID,
                    within: search,
                    version: RecordingEvidencePolicy.version,
                )
                let contexts = segments.compactMap { segment -> RecordingDayCoverage.Context? in
                    guard case let .established(context) = segment.resolution else { return nil }
                    return .init(period: segment.period, calendarContext: context)
                }
                switch try RecordingDayCoverage.resolve(
                    day: day,
                    within: search,
                    contexts: contexts,
                ) {
                    case let .needsContext(missing):
                        return .needsCalendarContext(.init(
                            request: request,
                            evidence: evidence,
                            missingPeriods: missing,
                        ))
                    case let .resolved(coverage):
                        guard !coverage.isEmpty else { return .absentRecordingDay(request) }
                        periods = coverage
                }
                scope = .recordingDay(deviceID: deviceID, day: day)
        }
        // Only decisions that the preview observed and intends to replace enter this causal
        // frontier. New arrivals are compared as evidence, never silently added here at Save.
        let predecessors = Set(evidence.controls.sourceChoices.filter { choice in
            choice.periods.contains { old in periods.contains { old.overlaps($0) } }
        }.map(\.id))
        let decision = try HistoryDecision(
            id: .init(rawValue: UUID()),
            author: author,
            periods: periods,
            scope: scope,
            action: request.action,
            predecessors: predecessors,
            version: evidence.policyVersion,
        )
        try RecordingControl.source(decision).validate()
        return .ready(.init(
            ownerID: scopeID,
            request: request,
            evidence: evidence,
            decision: decision,
        ))
    }

    public func apply(_ proposal: RecordingChoiceReview.Proposal) async throws -> ApplyResult {
        try await Self.logger.measure(.save, budget: .seconds(2)) {
            guard proposal.ownerID == scopeID
            else { return try await .stale(review(proposal.request)) }
            let record = try RecordingControlCodec.encode(
                .source(proposal.decision),
                generationID: proposal.evidence.generationID,
            )
            for attempt in 0 ..< Self.maximumSaveAttempts {
                do {
                    let result = try await store.perform(
                        expectedDataGenerationID: proposal.evidence.generationID,
                    ) {
                        let controls = try await RecordingControlStore(store: store, policy: policy)
                            .snapshot()
                        if let committed = controls.records.first(where: { $0.id == record.id }) {
                            guard committed == record
                            else { throw DataCompatibilityError.conflictingRecord }
                            return ApplyResult.applied
                        }
                        let current = try await RecordingReviewReader(store: store, policy: policy)
                            .evidence(for: proposal.request)
                        guard current == proposal.evidence,
                              proposal.evidence.policyVersion == RecordingEvidencePolicy.version
                        else {
                            return try ApplyResult.stale(makeReview(
                                proposal.request,
                                evidence: current,
                            ))
                        }
                        #if DEBUG
                            await beforeWrite?()
                        #endif
                        try await RecordingControlStore(store: store, policy: policy).append(
                            [record],
                            expectedGenerationID: proposal.evidence.generationID,
                        )
                        return ApplyResult.applied
                    }
                    if case .applied = result { await onCommitted() }
                    return result
                } catch RecordingPersistenceError.dataGenerationChanged {
                    return try await .stale(review(proposal.request))
                } catch WhereStoreReadConflictError.changedDuringTransaction {
                    // Recheck the same proposal after rollback. If only unrelated data arrived,
                    // its relevant snapshot remains equal and no new user confirmation is needed.
                    if attempt + 1 == Self
                        .maximumSaveAttempts
                    {
                        throw WhereStoreReadConflictError.changedDuringTransaction
                    }
                }
            }
            preconditionFailure("A bounded save must return or throw on its final attempt.")
        }
    }
}
