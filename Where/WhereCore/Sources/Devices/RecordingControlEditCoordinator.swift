import Foundation

/// Reviews device and place controls through the same guarded write protocol as source choices.
/// Resume and undo differ only in their reviewed periods; neither erases an older operation.
public struct RecordingControlEditCoordinator: Sendable {
    struct ScopeID: Hashable { let rawValue: UUID }

    public struct Proposal: Hashable, Sendable {
        let ownerID: ScopeID
        public let edit: RecordingControlEdit
        public let evidence: RecordingReviewEvidence
        public let control: RecordingControl
    }

    public enum ApplyResult: Hashable, Sendable {
        case applied
        case stale(Proposal)
    }

    private static let logger = WhereLog.reporting(RecordingControlEditCoordinatorLog.self)
    private let store: any WhereStore
    private let policy: DataCompatibilityPolicy
    private let author: RecordingDeviceID
    private let scopeID = ScopeID(rawValue: UUID())
    private let onCommitted: @Sendable () async -> Void

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

    public func review(_ edit: RecordingControlEdit) async throws -> Proposal {
        try await Self.logger.measure(.review, budget: .seconds(2)) {
            // Invalid caller scope is not evidence of incompatible stored history.
            let query = try edit.query()
            return try await store.readSnapshot {
                let state = try await store.dataCompatibilityState()
                try state.validate(policy: policy)
                guard try await store.dataContractMajor() == RecordingEvidencePolicy.version.major,
                      policy.current == RecordingEvidencePolicy.version
                else {
                    throw DataCompatibilityError.activationNotReady
                }
                let reader = RecordingReviewReader(store: store, policy: policy)
                var edit = edit
                var query = query
                while true {
                    let evidence = try await reader.evidence(for: query)
                    let expanded = try edit.includingObservedIgnoreExtensions(evidence.controls)
                    guard expanded != edit else { return try prepare(edit, evidence: evidence) }
                    edit = expanded
                    query = try expanded.query()
                }
            }
        }
    }

    private func prepare(
        _ edit: RecordingControlEdit,
        evidence: RecordingReviewEvidence,
    ) throws -> Proposal {
        let control = try edit.prepare(operationID: UUID(), author: author, evidence: evidence)
        try control.validate()
        return Proposal(ownerID: scopeID, edit: edit, evidence: evidence, control: control)
    }

    public func apply(_ proposal: Proposal) async throws -> ApplyResult {
        try await Self.logger.measure(.save, budget: .seconds(2)) {
            guard proposal.ownerID == scopeID
            else { return try await .stale(review(proposal.edit)) }
            let record = try RecordingControlCodec.encode(
                proposal.control,
                generationID: proposal.evidence.generationID,
            )
            do {
                switch try await RecordingReviewTransaction(store: store, policy: policy)
                    .apply(record, reviewed: proposal.evidence)
                {
                    case .applied:
                        await onCommitted()
                        return .applied
                    case .changed:
                        return try await .stale(review(proposal.edit))
                }
            } catch RecordingPersistenceError.dataGenerationChanged {
                return try await .stale(review(proposal.edit))
            }
        }
    }
}
