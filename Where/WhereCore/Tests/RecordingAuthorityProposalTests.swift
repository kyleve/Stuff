import Foundation
import Testing
@testable import WhereCore

struct RecordingAuthorityProposalTests {
    @Test func secondaryCannotAdvanceVersion() throws {
        let fixture = RecordingAuthorityFixture()
        let state = try fixture.proposal(.initial, .claim, device: fixture.phone).result.authority
        #expect(throws: RecordingAuthorityError.ownerRequired) {
            try fixture.proposal(
                state,
                .upgrade,
                device: fixture.tablet,
                version: .init(rawValue: 2),
            )
        }
        #expect(state.requiredVersion == .initial)
    }

    @Test func handoffRetainsFloorAndChangesOwnership() throws {
        let fixture = RecordingAuthorityFixture()
        let claim = try fixture.proposal(.initial, .claim, device: fixture.phone)
        let request = try fixture.proposal(
            claim.result.authority,
            .requestHandoff,
            device: fixture.tablet,
            version: .init(rawValue: 2),
        )
        let requestID = try #require(request.result.pendingHandoff?.requestID)
        let transfer = try fixture.proposal(
            request.result.authority,
            .approveHandoff(requestID: requestID),
            device: fixture.phone,
        )
        #expect(transfer.result.owner.deviceID == fixture.tablet)
        #expect(transfer.result.owner.ownershipID != claim.result.owner.ownershipID)
        #expect(transfer.result.pendingHandoff == nil)
        #expect(transfer.result.requiredVersion == .initial)
    }

    @Test func upgradeInvalidatesEarlierHandoffReview() throws {
        let fixture = RecordingAuthorityFixture()
        let claim = try fixture.proposal(.initial, .claim, device: fixture.phone)
        let request = try fixture.proposal(
            claim.result.authority,
            .requestHandoff,
            device: fixture.tablet,
        )
        let upgraded = try fixture.proposal(
            request.result.authority,
            .upgrade,
            device: fixture.phone,
            version: .init(rawValue: 2),
        )
        #expect(upgraded.result.pendingHandoff == nil)
        #expect(throws: RecordingAuthorityError.unsupportedVersion) {
            try fixture.proposal(upgraded.result.authority, .recover(.keep), device: fixture.tablet)
        }
    }

    @Test(arguments: [RecordingRecoveryHistory.keep, .excludeAfterReplacement])
    func recoveryBindsChoiceToReplacedOwnership(choice: RecordingRecoveryHistory) throws {
        let fixture = RecordingAuthorityFixture()
        let claim = try fixture.proposal(.initial, .claim, device: fixture.phone)
        let recovery = try fixture.proposal(
            claim.result.authority,
            .recover(choice),
            device: fixture.tablet,
        )
        #expect(recovery.expected.owner == claim.result.owner)
        #expect(recovery.transition == .recover(choice))
        #expect(recovery.result.requiredVersion == claim.result.requiredVersion)

        let roundTrip = try JSONDecoder().decode(
            RecordingAuthorityRecord.Proposal.self,
            from: JSONEncoder().encode(RecordingAuthorityRecord.Proposal(recovery)),
        )
        #expect(try roundTrip.value == recovery)
    }
}
