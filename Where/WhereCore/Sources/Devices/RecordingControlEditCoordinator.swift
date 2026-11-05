import Foundation

/// Reviews device and place controls through the same guarded write protocol as source choices.
/// Resume and undo differ only in their reviewed periods; neither erases an older operation.
public struct RecordingControlEditCoordinator: Sendable {
    struct ScopeID: Hashable { let rawValue: UUID }

    public struct PreparedEdit: Hashable, Sendable {
        public let edit: RecordingControlEdit
        public let control: RecordingControl
    }

    public struct Proposal: Hashable, Sendable {
        let ownerID: ScopeID
        public let edits: [PreparedEdit]
        public let evidence: RecordingReviewEvidence
    }

    public enum ValidationError: Error, Equatable { case overlappingEdits }

    private enum Target: Hashable {
        case ignore(RecordingDeviceID)
        case place(RecordingPlace.ID)
        case calendar(RecordingDeviceID)

        init(_ edit: RecordingControlEdit) {
            self = switch edit {
                case let .ignore(deviceID, _, _): .ignore(deviceID)
                case let .ignoreEnd(value): .ignore(value.deviceID)
                case let .ignoreResume(value): .ignore(value.deviceID)
                case let .place(placeID, _, _): .place(placeID)
                case let .calendar(deviceID, _, _): .calendar(deviceID)
            }
        }
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
        try await review([edit])
    }

    public func ignoreHistory(for deviceID: RecordingDeviceID) async throws
        -> RecordingIgnoreHistory
    {
        try await Self.logger.measure(.history, budget: .seconds(2)) {
            try await store.readSnapshot {
                try await validateContract()
                return try await RecordingIgnoreHistory(
                    controls: RecordingControlStore(store: store, policy: policy).snapshot(),
                    deviceID: deviceID,
                    version: policy.current,
                )
            }
        }
    }

    /// Uses the exact displayed proposal; it neither reads new evidence nor creates a write permit.
    public func inspectIgnore(_ proposal: Proposal) throws -> RecordingIgnoreInspection {
        try Self.logger.measure(.previewIgnore, budget: .seconds(2)) {
            try RecordingIgnoreInspection(proposal: proposal, policy: policy)
        }
    }

    /// Review disjoint edits together, for example the offset segments of calendar recovery.
    /// The local commit is atomic; each envelope still retains its own remote-delivery scope.
    public func review(_ edits: [RecordingControlEdit]) async throws -> Proposal {
        try await Self.logger.measure(.review, budget: .seconds(2)) {
            // Invalid caller scope is not evidence of incompatible stored history.
            let query = try Self.query(for: edits)
            return try await store.readSnapshot {
                try await validateContract()
                let reader = RecordingReviewReader(store: store, policy: policy)
                var edits = edits
                var query = query
                while true {
                    let evidence = try await reader.evidence(for: query)
                    let expanded = try edits.map {
                        try $0.includingObservedIgnoreExtensions(evidence.controls)
                    }
                    guard expanded != edits else { return try prepare(edits, evidence: evidence) }
                    edits = expanded
                    query = try Self.query(for: expanded)
                }
            }
        }
    }

    private func validateContract() async throws {
        let state = try await store.dataCompatibilityState()
        try state.validate(policy: policy)
        guard try await store.dataContractMajor() == RecordingEvidencePolicy.version.major,
              policy.current == RecordingEvidencePolicy.version
        else { throw DataCompatibilityError.activationNotReady }
    }

    private func prepare(
        _ edits: [RecordingControlEdit],
        evidence: RecordingReviewEvidence,
    ) throws -> Proposal {
        let prepared = try edits.map { edit in
            let control = try edit.prepare(operationID: UUID(), author: author, evidence: evidence)
            try control.validate()
            return PreparedEdit(edit: edit, control: control)
        }
        return Proposal(ownerID: scopeID, edits: prepared, evidence: evidence)
    }

    private static func query(for edits: [RecordingControlEdit]) throws -> RecordingReviewQuery {
        var scopes: [Target: [RecordingPeriod]] = [:]
        var periods: [RecordingPeriod] = []
        var deviceIDs: Set<RecordingDeviceID> = []
        for edit in edits {
            let query = try edit.query()
            let target = Target(edit)
            let previous = scopes[target, default: []]
            guard !previous.contains(where: { existing in
                query.periods.contains { existing.overlaps($0) }
            }) else { throw ValidationError.overlappingEdits }
            scopes[target] = previous + query.periods
            periods += query.periods
            deviceIDs.formUnion(query.deviceIDs)
        }
        return try RecordingReviewQuery(periods: periods, deviceIDs: deviceIDs)
    }

    public func apply(_ proposal: Proposal) async throws -> ApplyResult {
        try await Self.logger.measure(.save, budget: .seconds(2)) {
            guard proposal.ownerID == scopeID
            else { return try await .stale(review(proposal.edits.map(\.edit))) }
            let records = try proposal.edits.map {
                try RecordingControlCodec.encode(
                    $0.control,
                    generationID: proposal.evidence.generationID,
                )
            }
            do {
                switch try await RecordingReviewTransaction(store: store, policy: policy)
                    .apply(records, reviewed: proposal.evidence)
                {
                    case .applied:
                        await onCommitted()
                        return .applied
                    case .changed:
                        return try await .stale(review(proposal.edits.map(\.edit)))
                }
            } catch RecordingPersistenceError.dataGenerationChanged {
                return try await .stale(review(proposal.edits.map(\.edit)))
            }
        }
    }
}
