import Foundation
import Testing
@testable import WhereCore

struct RecordingAuthorityRecordTests {
    /// Literal payload from the original synthesized authority format. Keep this independent of
    /// the current encoder so a domain refactor cannot silently rewrite saved event history.
    private static let claimJSON = #"""
    {
      "expected": { "requiredVersion": 1 },
      "result": {
        "revision": {
          "sequence": 1,
          "eventID": "store://recording-authority/00000000-0000-0000-0000-000000000001"
        },
        "owner": {
          "deviceID": "store://devices/00000000-0000-0000-0000-000000000002",
          "ownershipID": "store://recording-authority/00000000-0000-0000-0000-000000000001"
        },
        "requiredVersion": 1
      },
      "kind": "claim"
    }
    """#

    @Test func existingPayloadRoundTripsWithoutChangingItsShape() throws {
        let bytes = Data(Self.claimJSON.utf8)
        let record = try JSONDecoder().decode(RecordingAuthorityRecord.Proposal.self, from: bytes)
        let proposal = try record.value
        #expect(proposal.expected == .unclaimed)
        #expect(proposal.result.revision.sequence == 1)
        #expect(proposal.result.owner.deviceID.rawValue
            .uuidString == "00000000-0000-0000-0000-000000000002")
        let encoded = try JSONEncoder().encode(RecordingAuthorityRecord.Proposal(proposal))
        let before = try #require(JSONSerialization.jsonObject(with: bytes) as? NSDictionary)
        let after = try #require(JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
        #expect(before == after)
    }

    @Test func aPendingSidecarRequestUsesTheSameProposalPayload() throws {
        let json = "{\"selection\":\"recording-requested\",\"pendingTransition\":\(Self.claimJSON)}"
        let record = try JSONDecoder().decode(
            RecordingInstallationControl.Record.self,
            from: Data(json.utf8),
        )
        let value = try record.value
        #expect(value.selection == .recordingRequested)
        #expect(value.pendingTransition?.transition == .claim)
        let reloaded = try JSONDecoder().decode(
            RecordingInstallationControl.Record.self,
            from: JSONEncoder()
                .encode(RecordingInstallationControl.Record(value)),
        )
        #expect(try reloaded.value == value)
    }

    @Test func everyTransitionRetainsItsMeaningAcrossPersistence() throws {
        let fixture = RecordingAuthorityFixture()
        let claim = try fixture.proposal(.initial, .claim, device: fixture.phone)
        let request = try fixture.proposal(
            claim.result.authority,
            .requestHandoff,
            device: fixture.tablet,
        )
        let requestID = try #require(request.result.pendingHandoff?.requestID)
        let cancel = try fixture.proposal(
            request.result.authority,
            .cancelHandoff(requestID: requestID),
            device: fixture.tablet,
        )
        let transfer = try fixture.proposal(
            request.result.authority,
            .approveHandoff(requestID: requestID),
            device: fixture.phone,
        )
        let keep = try fixture.proposal(
            claim.result.authority,
            .recover(.keep),
            device: fixture.tablet,
        )
        let exclude = try fixture.proposal(
            claim.result.authority,
            .recover(.excludeAfterReplacement),
            device: fixture.tablet,
        )
        let upgrade = try fixture.proposal(
            request.result.authority,
            .upgrade,
            device: fixture.phone,
            version: .init(rawValue: 2),
        )
        for proposal in [claim, request, cancel, transfer, keep, exclude, upgrade] {
            let commit = RecordingAuthorityCommit(
                proposal: proposal,
                committedAt: Date(timeIntervalSince1970: 100),
            )
            let data = try JSONEncoder().encode(RecordingAuthorityRecord.Commit(commit))
            let decoded = try JSONDecoder().decode(RecordingAuthorityRecord.Commit.self, from: data)
            #expect(try decoded.value == commit)
        }
    }

    enum Corruption: CaseIterable {
        case missingOwner, missingRevision, zeroRevision, skippedRevision, wrongKind,
             irrelevantRecoveryChoice
    }

    @Test(arguments: Corruption.allCases)
    func malformedRecordsNeverBecomeDomainProposals(_ corruption: Corruption) throws {
        var object = try #require(JSONSerialization
            .jsonObject(with: Data(Self.claimJSON.utf8)) as? [String: Any])
        var result = try #require(object["result"] as? [String: Any])
        var revision = try #require(result["revision"] as? [String: Any])
        switch corruption {
            case .missingOwner: result.removeValue(forKey: "owner")
            case .missingRevision: result.removeValue(forKey: "revision")
            case .zeroRevision:
                revision["sequence"] = 0
                result["revision"] = revision
            case .skippedRevision:
                revision["sequence"] = 2
                result["revision"] = revision
            case .wrongKind: object["kind"] = "upgrade"
            case .irrelevantRecoveryChoice: object["recoveryHistory"] = "keep"
        }
        object["result"] = result
        let record = try JSONDecoder().decode(
            RecordingAuthorityRecord.Proposal.self,
            from: JSONSerialization.data(withJSONObject: object),
        )
        #expect(throws: RecordingAuthorityError.invalidRecord) { try record.value }
    }
}
