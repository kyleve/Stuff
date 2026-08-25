import Testing
@testable import ThrowCore

struct ThrowLogTests {
    @Test func failureCategoryIsClosedAndCredentialFree() {
        #expect(AircraftPollingLogEvent.FailureCategory.allCases.count == 15)
        let event = AircraftPollingLogEvent(
            kind: .requestFailed,
            source: .adsbExchangeRapidAPI,
            requestCount: 1,
            durationMilliseconds: 20,
            httpStatus: 401,
            decodedAircraftCount: nil,
            backoffSeconds: nil,
            failureCategory: .invalidCredential,
        )
        #expect(event.message.contains("credential-sentinel") == false)
        #expect(event.remoteFields.isEmpty)
        #expect(
            AircraftPollingLogEvent.FailureCategory.transportLocalNetworkDenied.rawValue ==
                "transport-local-network-denied",
        )
    }

    @Test func geographyFailureIsRedactedAndClosed() {
        #expect(GeographyLogEvent.FailureCategory.allCases.count == 3)
        let event = GeographyLogEvent(failureCategory: .invalidArchive)

        #expect(event.message == "Bundled geography load failed: invalid-archive")
        #expect(event.remoteMessage == "Bundled geography load failed")
        #expect(event.remoteFields.isEmpty)
    }
}
