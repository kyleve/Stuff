import Foundation

/// The account's recording owner and shared data requirement after one committed transition.
///
/// `revision` advances for every transition. `owner.ownershipID` changes only when ownership
/// changes.
/// A pending request leaves the existing owner in place until approval or forced recovery.
/// This value describes authority, not local consent or whether GPS is currently running.
/// The protocol walkthrough lives in WhereCore/RECORDING_AUTHORITY.md.
public struct RecordingAuthority: Codable, Sendable, Equatable {
    /// Stable identity for one immutable coordination event and recording ownership period.
    public struct EventID: Hashable, Sendable, WhereStoreURLCodable {
        public let rawValue: UUID
        public init(rawValue: UUID) {
            self.rawValue = rawValue
        }

        public var storeURL: URL {
            StoreURL.url(
                collection: "recording-authority",
                type: rawValue.uuidString,
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

    /// One position in server history. The event ID also names the immutable commit.
    public struct Revision: Codable, Hashable, Sendable {
        public let sequence: UInt64
        public let eventID: EventID
    }

    /// One installation's ownership grant. Each new grant has a distinct `ownershipID`.
    public struct Owner: Codable, Sendable, Hashable {
        public let deviceID: RecordingDeviceID
        public let ownershipID: EventID
    }

    /// A request to replace a specific ownership period, including the requester's supported data
    /// version.
    /// The current owner remains authorized until it commits approval after stopping capture.
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

public enum RecordingAuthorityError: LocalizedError, Sendable, Equatable {
    case invalidRecord
    case conflict
    case ownerRequired
    case alreadyOwned
    case invalidHandoff
    case unsupportedVersion
    case revisionExhausted
    case authorityDisappeared

    public var errorDescription: String? {
        switch self {
            case .invalidRecord, .authorityDisappeared:
                String(localized: .recordingAuthorityVerificationFailed)
            case .conflict, .invalidHandoff:
                String(localized: .recordingAuthorityChanged)
            case .ownerRequired, .alreadyOwned:
                String(localized: .recordingAuthorityOwnerRequired)
            case .unsupportedVersion:
                String(localized: .recordingAuthorityUpdateRequired)
            case .revisionExhausted:
                String(localized: .recordingAuthorityRevisionExhausted)
        }
    }
}

/// User-selected treatment of automatic history from a forcibly replaced ownership period.
public enum RecordingRecoveryHistory: String, Codable, Sendable {
    case keep
    case excludeAfterReplacement = "exclude-after-replacement"
}

/// A validated decision bound to the complete state the caller reviewed.
///
/// Construction derives `result` from `expected` without I/O. The transport later compares
/// `expected` with the server head and conditionally saves the transition under its event ID.
/// Retain this exact value across uncertain responses so a retry can find the original commit.
/// Approval requires the caller to durably stop capture first.
/// This type cannot enforce hardware state.
public struct RecordingAuthorityProposal: Sendable, Equatable, Codable {
    /// The persisted transition category. `Action` is the caller-facing command that produces it.
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

    /// A caller's intent. Construction validates it against the reviewed authority.
    public enum Action: Sendable {
        case claim
        case requestHandoff
        case cancelHandoff(requestID: RecordingAuthority.EventID)
        /// Transfers the grant after the current owner durably prevents further capture.
        case approveHandoff(requestID: RecordingAuthority.EventID)
        /// Replaces an unreachable owner. An offline device can still capture.
        case recover(RecordingRecoveryHistory)
        /// Raises the shared floor to `buildVersion`. Installation alone does not raise it.
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
                owner = .init(deviceID: deviceID, ownershipID: eventID)
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
                owner = .init(deviceID: pending.requestedBy, ownershipID: eventID)
                handoff = nil
                kind = .transfer
                history = nil
            case let .recover(choice):
                guard let previous = owner,
                      previous.deviceID != deviceID
                else { throw RecordingAuthorityError.invalidHandoff }
                owner = .init(deviceID: deviceID, ownershipID: eventID)
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

    /// Reconstructs a decoded proposal through the same initializer used by live commands.
    ///
    /// Valid endpoints alone do not establish a legal transition between them.
    /// Reconstruction also checks the revision, ownership period, pending request, and recovery
    /// choice.
    /// This checks protocol shape. It does not authenticate the claimed device identity.
    public func validate() throws {
        guard let revision = result.revision else { throw RecordingAuthorityError.invalidRecord }
        let device: RecordingDeviceID
        let action: Action
        let version: DataCompatibilityVersion
        // The proposal stores a state transition, not the caller's full context. Use the minimum
        // compatible version unless the request or upgrade preserves a specific version itself.
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
                // Either participant can cancel with the same result. Reconstructing as the owner
                // validates that shape without claiming which participant submitted the command.
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

/// Proof that one proposal committed, even if a later transition changed the current owner.
///
/// CloudKit supplies `committedAt` from the immutable event's creation date.
/// Recovery uses that server time as its history cutoff.
/// Retrying the proposal returns this same commit and timestamp.
public struct RecordingAuthorityCommit: Codable, Sendable, Equatable {
    public let proposal: RecordingAuthorityProposal
    public let committedAt: Date

    public init(proposal: RecordingAuthorityProposal, committedAt: Date) {
        self.proposal = proposal
        self.committedAt = committedAt
    }
}

extension RecordingAuthority {
    static func resolve(commits input: [RecordingAuthorityCommit]) throws -> Self {
        let commits = input.sorted {
            ($0.proposal.result.revision?.sequence ?? 0) <
                ($1.proposal.result.revision?.sequence ?? 0)
        }
        var state = RecordingAuthority.initial
        for commit in commits {
            try commit.proposal.validate()
            guard commit.proposal.expected == state
            else { throw RecordingAuthorityError.invalidRecord }
            state = commit.proposal.result
        }
        return state
    }
}
