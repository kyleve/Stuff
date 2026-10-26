import Foundation

/// The account's initial state or an established ownership grant. Local consent and GPS
/// activity are independent. Persist through `RecordingAuthorityRecord` at storage boundaries.
public enum RecordingAuthority: Sendable, Equatable {
    case unclaimed
    case established(Established)

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

    /// Every committed transition has both an owner and a positive history revision.
    /// A pending handoff always replaces this owner and supports the existing floor.
    public struct Established: Sendable, Equatable {
        public let revision: Revision
        public let owner: Owner
        public let pendingHandoff: Handoff?
        public let requiredVersion: DataCompatibilityVersion

        init(
            revision: Revision,
            owner: Owner,
            pendingHandoff: Handoff?,
            requiredVersion: DataCompatibilityVersion,
        ) throws {
            guard revision.sequence > 0 else { throw RecordingAuthorityError.invalidRecord }
            if let pendingHandoff {
                guard pendingHandoff.replacing == owner,
                      pendingHandoff.requestedBy != owner.deviceID,
                      pendingHandoff.supportedVersion >= requiredVersion
                else { throw RecordingAuthorityError.invalidRecord }
            }
            self.revision = revision
            self.owner = owner
            self.pendingHandoff = pendingHandoff
            self.requiredVersion = requiredVersion
        }

        public var authority: RecordingAuthority {
            .established(self)
        }
    }

    public static let initial = Self.unclaimed

    public var revision: Revision? {
        switch self {
            case .unclaimed: nil
            case let .established(value): value.revision
        }
    }

    public var owner: Owner? {
        switch self {
            case .unclaimed: nil
            case let .established(value): value.owner
        }
    }

    public var pendingHandoff: Handoff? {
        switch self {
            case .unclaimed: nil
            case let .established(value): value.pendingHandoff
        }
    }

    public var requiredVersion: DataCompatibilityVersion {
        switch self {
            case .unclaimed: .initial
            case let .established(value): value.requiredVersion
        }
    }

    static func resolve(commits input: [RecordingAuthorityCommit]) throws -> Self {
        let commits = input
            .sorted { $0.proposal.result.revision.sequence < $1.proposal.result.revision.sequence }
        var state = RecordingAuthority.initial
        for commit in commits {
            guard commit.proposal.expected == state
            else { throw RecordingAuthorityError.invalidRecord }
            state = commit.proposal.result.authority
        }
        return state
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
