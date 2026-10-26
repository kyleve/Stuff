import Foundation

/// Historical exclusion selected during forced replacement. Raw observations remain lossless.
public struct RecordingRecoveryExclusion: Identifiable, Codable, Hashable, Sendable {
    public let id: RecordingAuthority.EventID
    public let formerOwner: RecordingAuthority.Owner
    public let replacedAt: Date

    public init(
        id: RecordingAuthority.EventID,
        formerOwner: RecordingAuthority.Owner,
        replacedAt: Date,
    ) {
        self.id = id
        self.formerOwner = formerOwner
        self.replacedAt = replacedAt
    }

    public func validate() throws {
        guard replacedAt.timeIntervalSince1970.isFinite
        else { throw RecordingAuthorityError.invalidRecord }
    }

    public func excludes(_ sample: LocationSample) -> Bool {
        sample.recordingProvenance?.deviceID == formerOwner.deviceID
            && sample.recordingProvenance?.ownershipID == formerOwner.ownershipID
            && sample.timestamp >= replacedAt
    }

    static func from(_ commit: RecordingAuthorityCommit) throws -> Self? {
        guard case .recover(.excludeAfterReplacement) = commit.proposal.transition
        else { return nil }
        guard let owner = commit.proposal.expected.owner
        else { throw RecordingAuthorityError.invalidRecord }
        let result = Self(
            id: commit.proposal.result.revision.eventID,
            formerOwner: owner,
            replacedAt: commit.committedAt,
        )
        try result.validate()
        return result
    }
}
