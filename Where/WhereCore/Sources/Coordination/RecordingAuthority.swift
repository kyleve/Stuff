import Foundation

/// Server-serialized control state, independent of user-history generations.
public struct RecordingAuthority: Codable, Sendable, Equatable {
    /// Stable identity for one immutable coordination event and recording tenure.
    public struct EventID: Hashable, Sendable, WhereStoreURLCodable {
        public let rawValue: UUID
        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }

        public var storeURL: URL {
            StoreURL.url(
                collection: "recording-authority",
                type: rawValue.uuidString.lowercased(),
                items: [:],
            )
        }

        public init?(storeURL: URL) {
            guard let parts = StoreURL.parts(of: storeURL),
                  parts.collection == "recording-authority",
                  parts.items.isEmpty, let value = UUID(uuidString: parts.type) else { return nil }
            rawValue = value
        }
    }

    public struct Revision: Codable, Hashable, Sendable {
        public let sequence: UInt64
        public let eventID: EventID
    }

    public struct Owner: Codable, Sendable, Equatable {
        public let deviceID: RecordingDeviceID
        public let tenureID: EventID
    }

    public struct Handoff: Codable, Sendable, Equatable {
        public let requestID: EventID
        public let requestedBy: RecordingDeviceID
        public let supportedVersion: DataCompatibilityVersion
        public let replacing: Owner
    }

    public let revision: Revision?
    public let owner: Owner?
    public let pendingHandoff: Handoff?
    public let requiredVersion: DataCompatibilityVersion

    public static let initial = Self(
        revision: nil,
        owner: nil,
        pendingHandoff: nil,
        requiredVersion: .initial,
    )

    /// Validate decoded control records before using them as authority.
    public func validate() throws {
        guard let revision else {
            guard self == .initial else { throw RecordingAuthorityError.invalidRecord }
            return
        }
        guard revision.sequence > 0,
              owner != nil else { throw RecordingAuthorityError.invalidRecord }
        if let pendingHandoff {
            guard pendingHandoff.replacing == owner,
                  pendingHandoff.requestedBy != owner?.deviceID,
                  pendingHandoff.supportedVersion >= requiredVersion
            else {
                throw RecordingAuthorityError.invalidRecord
            }
        }
    }
}

public enum RecordingAuthorityError: Error, Sendable, Equatable {
    case invalidRecord
    case conflict
    case ownerRequired
    case alreadyOwned
    case invalidHandoff
    case unsupportedVersion
    case revisionExhausted
    case authorityDisappeared
}

/// User-selected treatment of automatic history from a forcibly replaced tenure.
public enum RecordingRecoveryHistory: String, Codable, Sendable {
    case keep
    case excludeAfterReplacement = "exclude-after-replacement"
}

/// A proposed transition is bound to the complete state the caller reviewed.
/// Approval is issued only after the old recorder has durably relinquished capture.
public struct RecordingAuthorityProposal: Sendable, Equatable, Codable {
    public enum Kind: String, Codable, Sendable {
        case claim
        case request
        case cancel
        case transfer
        case recover
        case upgrade
    }

    public let expected: RecordingAuthority
    public let result: RecordingAuthority
    public let kind: Kind
    public let recoveryHistory: RecordingRecoveryHistory?

    public enum Action: Sendable {
        case claim
        case requestHandoff
        case cancelHandoff(requestID: RecordingAuthority.EventID)
        case approveHandoff(requestID: RecordingAuthority.EventID)
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
        try state.validate()
        guard buildVersion >= state.requiredVersion
        else { throw RecordingAuthorityError.unsupportedVersion }
        let sequence = (state.revision?.sequence ?? 0).addingReportingOverflow(1)
        guard !sequence.overflow else { throw RecordingAuthorityError.revisionExhausted }
        var owner = state.owner
        var handoff = state.pendingHandoff
        var version = state.requiredVersion
        let history: RecordingRecoveryHistory?
        switch action {
            case .claim:
                guard owner == nil else { throw RecordingAuthorityError.alreadyOwned }
                owner = .init(deviceID: deviceID, tenureID: eventID)
                kind = .claim
                history = nil
            case .requestHandoff:
                guard let existingOwner = owner, existingOwner.deviceID != deviceID,
                      handoff == nil
                else {
                    throw RecordingAuthorityError.invalidHandoff
                }
                handoff = .init(
                    requestID: eventID,
                    requestedBy: deviceID,
                    supportedVersion: buildVersion,
                    replacing: existingOwner,
                )
                kind = .request
                history = nil
            case let .cancelHandoff(requestID):
                guard let pending = handoff, pending.requestID == requestID,
                      pending.requestedBy == deviceID || owner?.deviceID == deviceID
                else {
                    throw RecordingAuthorityError.invalidHandoff
                }
                handoff = nil
                kind = .cancel
                history = nil
            case let .approveHandoff(requestID):
                guard owner?.deviceID == deviceID
                else { throw RecordingAuthorityError.ownerRequired }
                guard let pending = handoff, pending.requestID == requestID,
                      pending.replacing == owner
                else {
                    throw RecordingAuthorityError.invalidHandoff
                }
                owner = .init(deviceID: pending.requestedBy, tenureID: eventID)
                handoff = nil
                kind = .transfer
                history = nil
            case let .recover(choice):
                guard let previous = owner,
                      previous.deviceID != deviceID
                else { throw RecordingAuthorityError.invalidHandoff }
                owner = .init(deviceID: deviceID, tenureID: eventID)
                handoff = nil
                kind = .recover
                history = choice
            case .upgrade:
                guard owner?.deviceID == deviceID
                else { throw RecordingAuthorityError.ownerRequired }
                guard buildVersion > version
                else { throw RecordingAuthorityError.unsupportedVersion }
                version = buildVersion
                // A request reviewed against the earlier contract must be reviewed again.
                handoff = nil
                kind = .upgrade
                history = nil
        }
        expected = state
        result = .init(
            revision: .init(sequence: sequence.partialValue, eventID: eventID),
            owner: owner,
            pendingHandoff: handoff,
            requiredVersion: version,
        )
        recoveryHistory = history
        try result.validate()
    }

    /// Reconstruct decoded transitions so valid-looking states cannot bypass transition rules.
    public func validate() throws {
        guard let revision = result.revision else { throw RecordingAuthorityError.invalidRecord }
        let device: RecordingDeviceID
        let action: Action
        let version: DataCompatibilityVersion
        switch kind {
            case .claim:
                guard let owner = result.owner else { throw RecordingAuthorityError.invalidRecord }
                device = owner.deviceID
                action = .claim
                version = expected.requiredVersion
            case .request:
                guard let pending = result.pendingHandoff
                else { throw RecordingAuthorityError.invalidRecord }
                device = pending.requestedBy
                action = .requestHandoff
                version = pending.supportedVersion
            case .cancel, .transfer:
                guard let pending = expected.pendingHandoff,
                      let owner = expected.owner
                else { throw RecordingAuthorityError.invalidRecord }
                device = owner.deviceID
                action = kind == .cancel ? .cancelHandoff(requestID: pending.requestID) :
                    .approveHandoff(requestID: pending.requestID)
                version = expected.requiredVersion
            case .recover:
                guard let owner = result.owner,
                      let recoveryHistory else { throw RecordingAuthorityError.invalidRecord }
                device = owner.deviceID
                action = .recover(recoveryHistory)
                version = expected.requiredVersion
            case .upgrade:
                guard let owner = expected.owner
                else { throw RecordingAuthorityError.invalidRecord }
                device = owner.deviceID
                action = .upgrade
                version = result.requiredVersion
        }
        let reconstructed = try Self(
            state: expected,
            action: action,
            deviceID: device,
            buildVersion: version,
            eventID: revision.eventID,
        )
        guard reconstructed == self else { throw RecordingAuthorityError.invalidRecord }
    }
}

/// Immutable server receipt; the timestamp defines recovery history cutoffs.
public struct RecordingAuthorityCommit: Codable, Sendable, Equatable {
    public let proposal: RecordingAuthorityProposal
    public let committedAt: Date

    public init(proposal: RecordingAuthorityProposal, committedAt: Date) {
        self.proposal = proposal
        self.committedAt = committedAt
    }
}
