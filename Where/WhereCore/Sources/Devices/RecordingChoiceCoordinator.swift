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
    private let store: any WhereStore
    private let policy: DataCompatibilityPolicy
    private let author: RecordingDeviceID
    private let geography: HistoryRegionAttribution
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
        geography: HistoryRegionAttribution,
        onCommitted: @escaping @Sendable () async -> Void,
    ) {
        self.store = store
        self.policy = policy
        self.author = author
        self.geography = geography
        self.onCommitted = onCommitted
    }

    public func review(_ request: RecordingChoiceRequest) async throws -> RecordingChoiceReview {
        try await Self.logger.measure(.review, budget: .seconds(2)) {
            // Invalid caller input is not corrupt stored history. Validate it before admission,
            // whose fail-closed error handling must still revoke genuinely unreadable records.
            let query = try request.query()
            return try await store.readSnapshot {
                let state = try await store.dataCompatibilityState()
                try state.validate(policy: policy)
                guard try await store.dataContractMajor() == RecordingEvidencePolicy.version.major,
                      policy.current == RecordingEvidencePolicy.version
                else {
                    throw DataCompatibilityError.activationNotReady
                }
                let evidence = try await RecordingReviewReader(store: store, policy: policy)
                    .evidence(for: query)
                return try makeReview(request, evidence: evidence)
            }
        }
    }

    public func inspect(_ request: RecordingChoiceRequest) async throws
        -> RecordingChoiceInspection
    {
        try await inspection(of: review(request))
    }

    /// A stale Apply returns a new review. Build its preview without creating another proposal
    /// or adopting decisions that arrived after that guarded refresh.
    public func inspection(of review: RecordingChoiceReview) async throws
        -> RecordingChoiceInspection
    {
        try await Self.logger.measure(.preview, budget: .seconds(2)) {
            switch review {
                case let .ready(proposal):
                    guard proposal.ownerID == scopeID else {
                        throw DataCompatibilityError.concurrentChange
                    }
                    return try await RecordingChoiceInspection(
                        proposal: proposal,
                        catalog: geography.snapshot(),
                        policy: policy,
                    )
                case let .needsCalendarContext(clarification):
                    return .needsCalendarContext(clarification)
                case let .absentRecordingDay(request):
                    return .absentRecordingDay(request)
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
                switch try RecordingDayCoverage.resolve(
                    day: day,
                    deviceID: deviceID,
                    within: search,
                    decisions: evidence.controls.calendarContexts,
                    samples: Array(evidence.samples),
                    version: RecordingEvidencePolicy.version,
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
            var transaction = RecordingReviewTransaction(store: store, policy: policy)
            #if DEBUG
                transaction.beforeWrite = beforeWrite
            #endif
            do {
                switch try await transaction.apply(record, reviewed: proposal.evidence) {
                    case .applied:
                        await onCommitted()
                        return .applied
                    case let .changed(current):
                        return try .stale(makeReview(proposal.request, evidence: current))
                }
            } catch RecordingPersistenceError.dataGenerationChanged {
                return try await .stale(review(proposal.request))
            }
        }
    }
}
