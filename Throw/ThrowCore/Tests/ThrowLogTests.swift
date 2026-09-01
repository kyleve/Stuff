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
            decodingDiagnostics: nil,
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

    @Test func routeOutcomesAreClosedAndCarryNoRouteValues() {
        #expect(FlightRouteLogEvent.Outcome.allCases.count == 4)
        let event = FlightRouteLogEvent(outcome: .transportFailed)

        #expect(event.message == "Flight route enrichment transport-failed")
        #expect(event.remoteFields.isEmpty)
    }

    @Test func projectionMotionContainsOnlyAggregateValues() {
        let event = ProjectionMotionLogEvent(
            framesPerSecond: 29.8,
            aircraftCount: 42,
            usableHorizontalMotionPercent: 95,
            positionDerivedMotionPercent: 5,
            meanSampleAgeSeconds: 3,
            meanProjectedSpeedPerSecond: 0.001,
            meanCorrectionDistance: 0.002,
            previousSnapshotRetainedPercent: 80,
        )

        #expect(event.message == "Projection motion aggregate")
        #expect(event.remoteFields.isEmpty)
    }
}
