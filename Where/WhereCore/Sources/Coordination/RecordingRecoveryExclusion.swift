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
            && sample.recordingProvenance?.tenureID == formerOwner.tenureID
            && sample.timestamp >= replacedAt
    }

    static func from(_ commit: RecordingAuthorityCommit) throws -> Self? {
        guard commit.proposal.kind == .recover,
              commit.proposal.recoveryHistory == .excludeAfterReplacement else { return nil }
        guard let owner = commit.proposal.expected.owner,
              let eventID = commit.proposal.result.revision?.eventID
        else { throw RecordingAuthorityError.invalidRecord }
        let result = Self(id: eventID, formerOwner: owner, replacedAt: commit.committedAt)
        try result.validate()
        return result
    }
}
