import Foundation
import Testing
@testable import WhereCore

struct RecordingAuthorityTests {
    @Test func unclaimedAuthorityHasOnlyTheInitialFloor() {
        let state = RecordingAuthority.unclaimed
        #expect(state.owner == nil)
        #expect(state.revision == nil)
        #expect(state.pendingHandoff == nil)
        #expect(state.requiredVersion == .initial)
    }

    @Test func establishedAuthorityRejectsAnUnrelatedHandoff() throws {
        let fixture = RecordingAuthorityFixture()
        let first = try fixture.proposal(.unclaimed, .claim, device: fixture.phone).result
        let other = try fixture.proposal(.unclaimed, .claim, device: fixture.tablet).result
        #expect(throws: RecordingAuthorityError.invalidRecord) {
            try RecordingAuthority.Established(
                revision: first.revision,
                owner: first.owner,
                pendingHandoff: .init(
                    requestID: .init(rawValue: UUID()),
                    requestedBy: fixture.tablet,
                    supportedVersion: .initial,
                    replacing: other.owner,
                ),
                requiredVersion: .initial,
            )
        }
    }
}
