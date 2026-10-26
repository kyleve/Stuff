import CloudKit
import Foundation

/// The private-zone record shape for authority heads and immutable events.
/// Keeps record names, payload coding, and server commit metadata at the CloudKit boundary.
struct CloudKitRecordingAuthorityRecord {
    enum ID: Hashable {
        case head
        case event(RecordingAuthority.EventID)

        var recordID: CKRecord.ID {
            let name: String = switch self {
                case .head: "head"
                case let .event(eventID): eventID.rawValue.uuidString
            }
            return .init(recordName: name, zoneID: CloudKitRecordingAuthorityRecord.zoneID)
        }

        var recordType: CKRecord.RecordType {
            switch self {
                case .head: "WhereAuthorityHead"
                case .event: "WhereAuthorityEvent"
            }
        }
    }

    static let zoneID = CKRecordZone.ID(
        zoneName: "WhereRecordingAuthority",
        ownerName: CKCurrentUserDefaultName,
    )

    let record: CKRecord
    let id: ID

    init(record: CKRecord, id: ID) throws {
        guard record.recordType == id.recordType, record.recordID == id.recordID
        else { throw RecordingAuthorityError.invalidRecord }
        self.record = record
        self.id = id
    }

    init(id: ID, proposal: RecordingAuthorityProposal) throws {
        record = CKRecord(recordType: id.recordType, recordID: id.recordID)
        self.id = id
        try setProposal(proposal)
    }

    var proposal: RecordingAuthorityProposal {
        get throws {
            guard let payload = record["payload"] as? Data
            else { throw RecordingAuthorityError.invalidRecord }
            let proposal = try JSONDecoder().decode(
                RecordingAuthorityRecord.Proposal.self,
                from: payload,
            ).value
            try validate(proposal)
            return proposal
        }
    }

    /// Update the fetched object in place so its server change tag survives the conditional save.
    func setProposal(_ proposal: RecordingAuthorityProposal) throws {
        try validate(proposal)
        record["payload"] = try JSONEncoder()
            .encode(RecordingAuthorityRecord.Proposal(proposal)) as CKRecordValue
    }

    /// Only an immutable event has the server timestamp for a committed proposal.
    var commit: RecordingAuthorityCommit {
        get throws {
            guard case .event = id, let committedAt = record.creationDate
            else { throw RecordingAuthorityError.invalidRecord }
            return try .init(proposal: proposal, committedAt: committedAt)
        }
    }

    private func validate(_ proposal: RecordingAuthorityProposal) throws {
        if case let .event(eventID) = id, proposal.result.revision.eventID != eventID {
            throw RecordingAuthorityError.invalidRecord
        }
    }
}
