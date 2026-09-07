import Foundation
import Testing
@testable import ThrowCore

struct SourceHTTPValidationTests {
    @Test func finiteRetryAfterSecondsArePreserved() {
        let response = HTTPResponse(
            statusCode: 429,
            headers: ["Retry-After": " 180 "],
            data: Data(),
        )

        #expect(throws: AircraftSourceFailure.quotaReached(retryAfterSeconds: 180)) {
            try SourceHTTPValidation.validate(
                response,
                source: .adsbExchangeRapidAPI,
                receivedAt: ThrowCoreFixture.date,
            )
        }
    }

    @Test(arguments: ["inf", "+inf", "Infinity", "NaN"])
    func nonFiniteRetryAfterIsIgnored(value: String) {
        let response = HTTPResponse(
            statusCode: 429,
            headers: ["Retry-After": value],
            data: Data(),
        )

        #expect(throws: AircraftSourceFailure.quotaReached(retryAfterSeconds: nil)) {
            try SourceHTTPValidation.validate(
                response,
                source: .adsbExchangeRapidAPI,
                receivedAt: ThrowCoreFixture.date,
            )
        }
    }
}
