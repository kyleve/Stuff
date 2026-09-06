import Foundation
import Testing
@testable import ThrowCore

struct ThrowSoftwareCreditsLoadFailureTests {
    @Test func capturesTheUnderlyingErrorAsAValue() throws {
        let failure = ThrowSoftwareCreditsLoadFailure(
            error: NSError(
                domain: "com.stuff.throw.attribution-test",
                code: 42,
                userInfo: [NSLocalizedDescriptionKey: "Fixture manifest failure"],
            ),
        )

        #expect(failure.attachment.name == "attribution-error")
        #expect(failure.attachment.contentType == .json)
        let payload = try JSONDecoder().decode(
            [String: String].self,
            from: failure.attachment.data,
        )
        #expect(payload["domain"] == "com.stuff.throw.attribution-test")
        #expect(payload["code"] == "42")
        #expect(payload["description"]?.contains("Fixture manifest failure") == true)
    }
}
