import Foundation

/// A legal transition bound to the state reviewed by its caller. The result always establishes
/// ownership. Retry this exact value after an uncertain response; the server compares `expected`.
/// Transfer proposals express protocol intent, while the recording controller owns stop-and-drain.
public struct RecordingAuthorityProposal: Sendable, Equatable {
    /// Each transition carries only its own metadata. Recovery cannot omit its history choice.
    public enum Transition: Sendable, Equatable {
        case claim
        case request
        case cancel
        case transfer
        case recover(RecordingRecoveryHistory)
        case upgrade
    }

    /// Stable wire categories, derived from the domain transition rather than stored beside it.
    public enum Kind: String, Codable, Sendable {
        case claim, request, cancel, transfer, recover, upgrade
    }

    public let expected: RecordingAuthority
    public let result: RecordingAuthority.Established
    public let transition: Transition

    public var kind: Kind {
        switch transition {
            case .claim: .claim
            case .request: .request
            case .cancel: .cancel
            case .transfer: .transfer
            case .recover: .recover
            case .upgrade: .upgrade
        }
    }

    /// A caller's intent. Construction checks it against the reviewed authority.
    public enum Action: Sendable {
        case claim
        case requestHandoff
        case cancelHandoff(requestID: RecordingAuthority.RequestID)
        case approveHandoff(requestID: RecordingAuthority.RequestID)
        case recover(RecordingRecoveryHistory)
        case upgrade
    }

    public init(
        state: RecordingAuthority,
        action: Action,
        deviceID: RecordingDeviceID,
        buildVersion: DataCompatibilityVersion,
        eventID: RecordingAuthority.EventID,
    ) throws {
        guard buildVersion >= state.requiredVersion
        else { throw RecordingAuthorityError.unsupportedVersion }
        let sequence = (state.revision?.sequence ?? 0).addingReportingOverflow(1)
        guard !sequence.overflow else { throw RecordingAuthorityError.revisionExhausted }
        let owner: RecordingAuthority.Owner
        let handoff: RecordingAuthority.Handoff?
        var version = state.requiredVersion
        switch action {
            case .claim:
                guard case .unclaimed = state else { throw RecordingAuthorityError.alreadyOwned }
                owner = .init(deviceID: deviceID, ownershipID: .init(eventID: eventID))
                handoff = nil
                transition = .claim
            case .requestHandoff:
                guard let existingOwner = state.owner, existingOwner.deviceID != deviceID,
                      state.pendingHandoff == nil
                else { throw RecordingAuthorityError.invalidHandoff }
                owner = existingOwner
                handoff = .init(
                    requestID: .init(eventID: eventID),
                    requestedBy: deviceID,
                    supportedVersion: buildVersion,
                    replacing: existingOwner,
                )
                transition = .request
            case let .cancelHandoff(requestID):
                guard let existingOwner = state.owner, let pending = state.pendingHandoff,
                      pending.requestID == requestID,
                      pending.requestedBy == deviceID || existingOwner.deviceID == deviceID
                else { throw RecordingAuthorityError.invalidHandoff }
                owner = existingOwner
                handoff = nil
                transition = .cancel
            case let .approveHandoff(requestID):
                guard let existingOwner = state.owner, existingOwner.deviceID == deviceID
                else { throw RecordingAuthorityError.ownerRequired }
                guard let pending = state.pendingHandoff, pending.requestID == requestID
                else { throw RecordingAuthorityError.invalidHandoff }
                owner = .init(deviceID: pending.requestedBy, ownershipID: .init(eventID: eventID))
                handoff = nil
                transition = .transfer
            case let .recover(choice):
                guard let previous = state.owner, previous.deviceID != deviceID
                else { throw RecordingAuthorityError.invalidHandoff }
                owner = .init(deviceID: deviceID, ownershipID: .init(eventID: eventID))
                handoff = nil
                transition = .recover(choice)
            case .upgrade:
                guard let existingOwner = state.owner, existingOwner.deviceID == deviceID
                else { throw RecordingAuthorityError.ownerRequired }
                guard buildVersion > version
                else { throw RecordingAuthorityError.unsupportedVersion }
                owner = existingOwner
                version = buildVersion
                // A request reviewed against the earlier contract must be reviewed again.
                handoff = nil
                transition = .upgrade
        }
        expected = state
        result = try .init(
            revision: .init(sequence: sequence.partialValue, eventID: eventID),
            owner: owner,
            pendingHandoff: handoff,
            requiredVersion: version,
        )
    }
}

/// A committed transition and its server-assigned time. A retry retains both values even after
/// later transitions. Recovery uses `committedAt` as its historical exclusion cutoff.
public struct RecordingAuthorityCommit: Sendable, Equatable {
    public let proposal: RecordingAuthorityProposal
    public let committedAt: Date

    public init(proposal: RecordingAuthorityProposal, committedAt: Date) {
        self.proposal = proposal
        self.committedAt = committedAt
    }
}
