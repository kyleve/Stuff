import CloudKit
import Foundation
import Testing
@testable import WhereCore

struct CloudKitRecordingAuthorityTransportTests {
    @Test func missingPayloadFailsClosed() {
        let record = CKRecord(recordType: "WhereAuthorityHead")
        #expect(throws: RecordingAuthorityError.invalidRecord) {
            try CloudKitRecordingAuthorityTransport.decode(record)
        }
    }

    @Test func malformedTransitionCannotAuthorizeRecording() throws {
        let fixture = RecordingAuthorityFixture()
        let proposal = try fixture.proposal(.initial, .claim, device: fixture.phone)
        var object = try #require(JSONSerialization
            .jsonObject(with: JSONEncoder().encode(proposal)) as? [String: Any])
        object["kind"] = "upgrade"
        let record = CKRecord(recordType: "WhereAuthorityHead")
        record["payload"] = try JSONSerialization.data(withJSONObject: object) as CKRecordValue
        #expect(throws: RecordingAuthorityError.invalidRecord) {
            try CloudKitRecordingAuthorityTransport.decode(record)
        }
    }

    @Test func payloadRoundTripPreservesProposal() throws {
        let fixture = RecordingAuthorityFixture()
        let proposal = try fixture.proposal(.initial, .claim, device: fixture.phone)
        let record = CKRecord(recordType: "WhereAuthorityHead")
        record["payload"] = try JSONEncoder().encode(proposal) as CKRecordValue
        #expect(try CloudKitRecordingAuthorityTransport.decode(record) == proposal)
    }
}
