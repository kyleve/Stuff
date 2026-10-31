import CloudKit
import Foundation
import Testing
@testable import WhereCore

struct CloudKitRecordingAuthorityRecordTests {
    @Test func recordIdentityAndTypeMustMatch() throws {
        let otherZone = CKRecordZone.ID(
            zoneName: "different-zone",
            ownerName: CKCurrentUserDefaultName,
        )
        let records = [
            CKRecord(
                recordType: "WhereAuthorityEvent",
                recordID: CloudKitRecordingAuthorityRecord.ID.head.recordID,
            ),
            CKRecord(
                recordType: "WhereAuthorityHead",
                recordID: .init(
                    recordName: "not-head",
                    zoneID: CloudKitRecordingAuthorityRecord.zoneID,
                ),
            ),
            CKRecord(
                recordType: "WhereAuthorityHead",
                recordID: .init(recordName: "head", zoneID: otherZone),
            ),
        ]
        for record in records {
            #expect(throws: RecordingAuthorityError.invalidRecord) {
                try CloudKitRecordingAuthorityRecord(record: record, id: .head)
            }
        }
    }

    @Test func eventIdentityMustMatchItsProposal() throws {
        let fixture = RecordingAuthorityFixture()
        let proposal = try fixture.proposal(.initial, .claim, device: fixture.phone)
        let recordID = CloudKitRecordingAuthorityRecord.ID.event(.init(rawValue: UUID()))
        let record = CKRecord(recordType: recordID.recordType, recordID: recordID.recordID)
        record["payload"] = try JSONEncoder().encode(proposal) as CKRecordValue
        let wrapped = try CloudKitRecordingAuthorityRecord(record: record, id: recordID)
        #expect(throws: RecordingAuthorityError.invalidRecord) { try wrapped.proposal }
        #expect(throws: RecordingAuthorityError.invalidRecord) {
            try CloudKitRecordingAuthorityRecord(id: recordID, proposal: proposal)
        }
    }

    @Test func updatingAHeadRetainsTheFetchedRecord() throws {
        let fixture = RecordingAuthorityFixture()
        let claim = try fixture.proposal(.initial, .claim, device: fixture.phone)
        let head = try CloudKitRecordingAuthorityRecord(id: .head, proposal: claim)
        let fetchedRecord = head.record
        let recovered = try fixture.proposal(claim.result, .recover(.keep), device: fixture.tablet)
        try head.setProposal(recovered)
        #expect(head.record === fetchedRecord)
        #expect(try head.proposal == recovered)
    }

    @Test func anUnsavedEventCannotSupplyAServerCommitTime() throws {
        let fixture = RecordingAuthorityFixture()
        let proposal = try fixture.proposal(.initial, .claim, device: fixture.phone)
        let eventID = try #require(proposal.result.revision?.eventID)
        let event = try CloudKitRecordingAuthorityRecord(id: .event(eventID), proposal: proposal)
        #expect(throws: RecordingAuthorityError.invalidRecord) { try event.commit }
        let head = try CloudKitRecordingAuthorityRecord(id: .head, proposal: proposal)
        #expect(throws: RecordingAuthorityError.invalidRecord) { try head.commit }
    }

    @Test func missingPayloadFailsClosed() {
        let record = CKRecord(
            recordType: "WhereAuthorityHead",
            recordID: CloudKitRecordingAuthorityRecord.ID.head.recordID,
        )
        #expect(throws: RecordingAuthorityError.invalidRecord) {
            try CloudKitRecordingAuthorityRecord(record: record, id: .head).proposal
        }
    }

    @Test func malformedTransitionCannotAuthorizeRecording() throws {
        let fixture = RecordingAuthorityFixture()
        let proposal = try fixture.proposal(.initial, .claim, device: fixture.phone)
        var object = try #require(JSONSerialization
            .jsonObject(with: JSONEncoder().encode(proposal)) as? [String: Any])
        object["kind"] = "upgrade"
        let record = CKRecord(
            recordType: "WhereAuthorityHead",
            recordID: CloudKitRecordingAuthorityRecord.ID.head.recordID,
        )
        record["payload"] = try JSONSerialization.data(withJSONObject: object) as CKRecordValue
        #expect(throws: RecordingAuthorityError.invalidRecord) {
            try CloudKitRecordingAuthorityRecord(record: record, id: .head).proposal
        }
    }

    @Test func payloadRoundTripPreservesProposal() throws {
        let fixture = RecordingAuthorityFixture()
        let proposal = try fixture.proposal(.initial, .claim, device: fixture.phone)
        let record = CKRecord(
            recordType: "WhereAuthorityHead",
            recordID: CloudKitRecordingAuthorityRecord.ID.head.recordID,
        )
        record["payload"] = try JSONEncoder().encode(proposal) as CKRecordValue
        #expect(try CloudKitRecordingAuthorityRecord(record: record, id: .head)
            .proposal == proposal)
    }
}
