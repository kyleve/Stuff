import Foundation
import Testing
@testable import WhereCore

struct DataCompatibilityFailureTests {
    @Test func blockingStatePreservesTheOriginalErrorAndItsUnderlyingCause() throws {
        let cause = NSError(domain: "ExampleTransport", code: 42)
        let error = NSError(domain: "ExampleVerification", code: 7, userInfo: [
            NSUnderlyingErrorKey: cause,
            NSLocalizedDescriptionKey: "Verification could not complete.",
        ])
        let failure = DataCompatibilityFailure(error)
        let state = DataCompatibilityState.verificationFailed(failure)
        guard case let .verificationFailed(blocked) = try #require(state.blockingError) else {
            Issue.record("A failed verification must remain blocking.")
            return
        }
        #expect(blocked == failure)
        let retained = blocked.error as NSError
        #expect(retained === error)
        #expect(retained.userInfo[NSUnderlyingErrorKey] as? NSError === cause)
        #expect(state != .verificationFailed(.init(error)))
    }
}
