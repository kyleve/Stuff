import Foundation
import Testing
@testable import WhereCore

struct RecordingAuthorityTests {
    @Test func secondaryCannotAdvanceVersion() throws {
        let fixture = RecordingAuthorityFixture()
        let state = try fixture.proposal(.initial, .claim, device: fixture.phone).result
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

    @Test func handoffRetainsFloorAndChangesTenure() throws {
        let fixture = RecordingAuthorityFixture()
        let claim = try fixture.proposal(.initial, .claim, device: fixture.phone)
        let request = try fixture.proposal(
            claim.result,
            .requestHandoff,
            device: fixture.tablet,
            version: .init(rawValue: 2),
        )
        let requestID = try #require(request.result.pendingHandoff?.requestID)
        let transfer = try fixture.proposal(
            request.result,
            .approveHandoff(requestID: requestID),
            device: fixture.phone,
        )
        #expect(transfer.result.owner?.deviceID == fixture.tablet)
        #expect(transfer.result.owner?.tenureID != claim.result.owner?.tenureID)
        #expect(transfer.result.pendingHandoff == nil)
        #expect(transfer.result.requiredVersion == .initial)
        try transfer.validate()
    }

    @Test func upgradeInvalidatesEarlierHandoffReview() throws {
        let fixture = RecordingAuthorityFixture()
        let claim = try fixture.proposal(.initial, .claim, device: fixture.phone)
        let request = try fixture.proposal(claim.result, .requestHandoff, device: fixture.tablet)
        let upgraded = try fixture.proposal(
            request.result,
            .upgrade,
            device: fixture.phone,
            version: .init(rawValue: 2),
        )
        #expect(upgraded.result.pendingHandoff == nil)
        #expect(throws: RecordingAuthorityError.unsupportedVersion) {
            try fixture.proposal(upgraded.result, .recover(.keep), device: fixture.tablet)
        }
    }

    @Test(arguments: [RecordingRecoveryHistory.keep, .excludeAfterReplacement])
    func recoveryBindsChoiceToReplacedTenure(choice: RecordingRecoveryHistory) throws {
        let fixture = RecordingAuthorityFixture()
        let claim = try fixture.proposal(.initial, .claim, device: fixture.phone)
        let recovery = try fixture.proposal(claim.result, .recover(choice), device: fixture.tablet)
        #expect(recovery.expected.owner == claim.result.owner)
        #expect(recovery.recoveryHistory == choice)
        #expect(recovery.result.requiredVersion == claim.result.requiredVersion)
        try recovery.validate()
        let roundTrip = try JSONDecoder().decode(
            RecordingAuthorityProposal.self,
            from: JSONEncoder().encode(recovery),
        )
        #expect(roundTrip == recovery)
    }
}
