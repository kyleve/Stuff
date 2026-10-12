import Foundation
import Testing
@testable import WhereCore

struct RecordingAuthorityTransportTests {
    @Test func competingClaimsHaveOneWinner() async throws {
        let fixture = RecordingAuthorityFixture()
        let server = LocalRecordingAuthorityTransport(now: { Date() })
        let phone = try fixture.proposal(.initial, .claim, device: fixture.phone)
        let tablet = try fixture.proposal(.initial, .claim, device: fixture.tablet)
        _ = try await server.commit(phone)
        await #expect(throws: RecordingAuthorityError.conflict) { try await server.commit(tablet) }
        #expect(try await server.current()?.proposal == phone)
    }

    @Test func retryAfterLaterTransitionReturnsOriginalReceipt() async throws {
        let fixture = RecordingAuthorityFixture()
        let server = LocalRecordingAuthorityTransport(now: { Date() })
        let claim = try fixture.proposal(.initial, .claim, device: fixture.phone)
        let receipt = try await server.commit(claim)
        let recovered = try fixture.proposal(claim.result, .recover(.keep), device: fixture.tablet)
        _ = try await server.commit(recovered)
        #expect(try await server.commit(claim) == receipt)
        #expect(try await server.current()?.proposal == recovered)
        let upgrade = try fixture.proposal(
            claim.result,
            .upgrade,
            device: fixture.phone,
            version: .init(rawValue: 2),
        )
        await #expect(throws: RecordingAuthorityError.conflict) { try await server.commit(upgrade) }
    }
}
