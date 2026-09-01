import Foundation
import Testing
@testable import ThrowCore

struct ThrowLogTests {
    @Test func coldLaunchFailuresExposeOnlyTheirTypedBoundary() {
        let event = ThrowSessionLogEvent.coldLaunchFailed(boundary: .credential)

        #expect(event.level == .error)
        #expect(event.message == "Cold launch failed at the credential boundary")
        #expect(event.remoteMessage == "Cold launch failed")
        #expect(event.remoteFields.count == 1)
        #expect(event.remoteFields.first?.key.rawValue == "boundary")
        guard case let .category(category) = event.remoteFields.first?.value else {
            Issue.record("The launch boundary must be a closed remote category")
            return
        }
        #expect(category.rawValue == "credential")
    }

    @Test func failureCategoryIsClosedAndCredentialFree() {
        #expect(AircraftPollingLogEvent.FailureCategory.allCases.count == 15)
        let event = AircraftPollingLogEvent.requestFailed(
            AircraftPollingLogEvent.RequestFailure(
                source: .adsbExchangeRapidAPI,
                requestCount: 1,
                durationMilliseconds: 20,
                httpStatus: 401,
                failureCategory: .invalidCredential,
            ),
        )
        #expect(event.message.contains("credential-sentinel") == false)
        #expect(event.remoteFields.isEmpty)
        #expect(
            AircraftPollingLogEvent.FailureCategory.transportLocalNetworkDenied.rawValue ==
                "transport-local-network-denied",
        )
    }

    @Test func pollingEventWireVocabularyAndVersionStayStable() {
        #expect(AircraftPollingLogEvent.eventName == "AircraftPollingLogEvent")
        #expect(AircraftPollingLogEvent.eventVersion == 3)
        #expect(AircraftPollingLogEvent.Kind.allCases.map(\.rawValue) == [
            "source-activated",
            "receiver-metadata-fallback",
            "request-succeeded",
            "partial-schema-drift",
            "request-failed",
            "retry-scheduled",
            "polling-stopped",
        ])
    }

    @Test func versionThreePayloadRoundTripsEachCaseSpecificEvent() throws {
        let diagnostics = AircraftSnapshotDecodingDiagnostics(
            malformedRecordCount: 2,
            missingPositionRecordCount: 3,
        )
        let discardedRecords = try #require(diagnostics.discardedRecords)
        let events: [AircraftPollingLogEvent] = [
            .sourceActivated(.init(source: .adsbLol)),
            .receiverMetadataFallback(.init(failureCategory: .transportOffline)),
            .requestSucceeded(
                .init(
                    source: .adsbLol,
                    requestCount: 4,
                    durationMilliseconds: 20,
                    httpStatus: 206,
                    decodedAircraftCount: 12,
                ),
            ),
            .partialSchemaDrift(
                .init(
                    source: .adsbLol,
                    requestCount: 4,
                    httpStatus: 206,
                    decodedAircraftCount: 12,
                    discardedRecords: discardedRecords,
                ),
            ),
            .requestFailed(
                .init(
                    source: .readsb,
                    requestCount: 5,
                    durationMilliseconds: 30,
                    httpStatus: nil,
                    failureCategory: .transportOffline,
                ),
            ),
            .retryScheduled(
                .init(
                    source: .readsb,
                    requestCount: 5,
                    httpStatus: nil,
                    decodedAircraftCount: 11,
                    backoffSeconds: 10,
                    failureCategory: .transportOffline,
                ),
            ),
            .pollingStopped(
                .init(source: .readsb, requestCount: 5, decodedAircraftCount: 11),
            ),
        ]

        for event in events {
            let data = try JSONEncoder().encode(event)
            #expect(try JSONDecoder().decode(AircraftPollingLogEvent.self, from: data) == event)
        }
    }

    @Test func partialSchemaDriftKeepsTheFlatVersionThreePayload() throws {
        let diagnostics = AircraftSnapshotDecodingDiagnostics(
            malformedRecordCount: 2,
            missingPositionRecordCount: 3,
        )
        let discardedRecords = try #require(diagnostics.discardedRecords)
        let event = AircraftPollingLogEvent.partialSchemaDrift(
            .init(
                source: .adsbLol,
                requestCount: 4,
                httpStatus: 206,
                decodedAircraftCount: 12,
                discardedRecords: discardedRecords,
            ),
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let payload = try #require(String(data: encoder.encode(event), encoding: .utf8))

        #expect(
            payload ==
                #"{"decodedAircraftCount":12,"decodingDiagnostics":{"malformedRecordCount":2,"missingPositionRecordCount":3},"httpStatus":206,"kind":"partial-schema-drift","requestCount":4,"source":"adsb-lol"}"#,
        )
    }

    @Test func versionThreeDecoderRejectsSchemaDriftWithoutDiscardedRecords() throws {
        let payload = Data(
            #"{"decodedAircraftCount":12,"decodingDiagnostics":{"malformedRecordCount":0,"missingPositionRecordCount":0},"kind":"partial-schema-drift","requestCount":4,"source":"adsb-lol"}"#
                .utf8,
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AircraftPollingLogEvent.self, from: payload)
        }
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
