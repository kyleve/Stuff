import Foundation
import PeriscopeCore
import Testing
@testable import ThrowCore

struct ThrowLogTests {
    @Test func coldLaunchFailuresExposeOnlyTheirTypedBoundary() {
        let error = NSError(domain: "cold-launch-private", code: 1)
        let event = ThrowSessionLog.ColdLaunchFailed(
            boundary: .shared(.category, .credential),
            error: .restricted(.errorDetails, error),
        )

        #expect(ThrowSessionLog.ColdLaunchFailed.eventName == "ThrowSession.cold-launch-failed")
        #expect(event.level == .error)
        #expect(event.message == "Cold launch failed at the credential boundary")
        #expect(event.classifiedFields == [
            .shareable(
                key: LogFieldKey("boundary"),
                kind: .category,
                value: .string("credential"),
            ),
            .restricted(key: LogFieldKey("error"), kind: .errorDetails),
        ])
    }

    @Test func softwareCreditsFailureContainsNoRawErrorText() {
        let errorSentinel = "credits-error-do-not-share"
        let event = ThrowSessionLog.SoftwareCreditsLoadFailed(
            error: .restricted(
                .errorDetails,
                NSError(
                    domain: "software-credits-private",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: errorSentinel],
                ),
            ),
        )

        #expect(
            ThrowSessionLog.SoftwareCreditsLoadFailed.eventName ==
                "ThrowSession.software-credits-load-failed",
        )
        #expect(event.level == .error)
        #expect(event.message == "Software credits failed to load")
        #expect(event.message.contains(errorSentinel) == false)
        #expect(event.classifiedFields == [
            .restricted(key: LogFieldKey("error"), kind: .errorDetails),
        ])
    }

    @Test func postLaunchFailuresExposeOnlyTheirTypedOperation() {
        let event = ThrowSessionLog.PostLaunchOperationFailed(
            operation: .shared(.category, .projectionPreparation),
            error: .restricted(
                .errorDetails,
                NSError(domain: "post-launch-private", code: 1),
            ),
        )

        #expect(
            ThrowSessionLog.PostLaunchOperationFailed.eventName ==
                "ThrowSession.post-launch-operation-failed",
        )
        #expect(event.level == .error)
        #expect(
            event.message ==
                "Post-launch operation failed at the projection-preparation boundary",
        )
        #expect(event.classifiedFields == [
            .shareable(
                key: LogFieldKey("operation"),
                kind: .category,
                value: .string("projection-preparation"),
            ),
            .restricted(key: LogFieldKey("error"), kind: .errorDetails),
        ])
    }

    @Test func postLaunchOperationVocabularyStaysClosed() {
        #expect(ThrowSessionLogEvent.PostLaunchOperation.allCases.map(\.rawValue) == [
            "preference-persistence",
            "aircraft-source",
            "rapidapi-credential",
            "flightradar24-credential",
            "location",
            "playlist",
            "onboarding",
            "projection-preparation",
            "projection-rendering",
        ])
    }

    @Test func failureCategoryIsClosedAndCredentialFree() {
        #expect(AircraftPollingLogEvent.FailureCategory.allCases.count == 15)
        let event = AircraftPollingLog.RequestFailed(
            source: .restricted(.category, .adsbExchangeRapidAPI),
            requestCount: .restricted(.count, 1),
            durationMilliseconds: .restricted(.duration, 20),
            httpStatus: .restricted(.technicalState, 401),
            failureCategory: .restricted(.category, .invalidCredential),
        )

        #expect(event.message.contains("credential-sentinel") == false)
        #expect(event.classifiedFields == [
            .restricted(key: LogFieldKey("source"), kind: .category),
            .restricted(key: LogFieldKey("request_count"), kind: .count),
            .restricted(key: LogFieldKey("duration_milliseconds"), kind: .duration),
            .restricted(key: LogFieldKey("http_status"), kind: .technicalState),
            .restricted(key: LogFieldKey("failure_category"), kind: .category),
        ])
        #expect(
            AircraftPollingLogEvent.FailureCategory.transportLocalNetworkDenied.rawValue ==
                "transport-local-network-denied",
        )
    }

    @Test func generatedPollingEventIdentitiesStayStable() {
        #expect([
            AircraftPollingLog.SourceActivated.eventName,
            AircraftPollingLog.ReceiverMetadataFallback.eventName,
            AircraftPollingLog.RequestSucceeded.eventName,
            AircraftPollingLog.PartialSchemaDrift.eventName,
            AircraftPollingLog.RequestFailed.eventName,
            AircraftPollingLog.RetryScheduled.eventName,
            AircraftPollingLog.PollingStopped.eventName,
        ] == [
            "AircraftPollingLogEvent.source-activated",
            "AircraftPollingLogEvent.receiver-metadata-fallback",
            "AircraftPollingLogEvent.request-succeeded",
            "AircraftPollingLogEvent.partial-schema-drift",
            "AircraftPollingLogEvent.request-failed",
            "AircraftPollingLogEvent.retry-scheduled",
            "AircraftPollingLogEvent.polling-stopped",
        ])
        #expect([
            AircraftPollingLog.SourceActivated.eventVersion,
            AircraftPollingLog.ReceiverMetadataFallback.eventVersion,
            AircraftPollingLog.RequestSucceeded.eventVersion,
            AircraftPollingLog.PartialSchemaDrift.eventVersion,
            AircraftPollingLog.RequestFailed.eventVersion,
            AircraftPollingLog.RetryScheduled.eventVersion,
            AircraftPollingLog.PollingStopped.eventVersion,
        ] == Array(repeating: 1, count: 7))
    }

    @Test func pollingSemanticEventsMapToConcreteDecodableEvents() throws {
        let diagnostics = AircraftSnapshotDecodingDiagnostics(
            malformedRecordCount: 2,
            missingPositionRecordCount: 3,
        )
        let discardedRecords = try #require(diagnostics.discardedRecords)
        let semanticEvents: [AircraftPollingLogEvent] = [
            .sourceActivated(.init(source: .adsbLol)),
            .receiverMetadataFallback(.init(failureCategory: .transportOffline)),
            .requestSucceeded(.init(
                source: .adsbLol,
                requestCount: 4,
                durationMilliseconds: 20,
                httpStatus: 206,
                decodedAircraftCount: 12,
            )),
            .partialSchemaDrift(.init(
                source: .adsbLol,
                requestCount: 4,
                httpStatus: 206,
                decodedAircraftCount: 12,
                discardedRecords: discardedRecords,
            )),
            .requestFailed(.init(
                source: .readsb,
                requestCount: 5,
                durationMilliseconds: 30,
                httpStatus: nil,
                failureCategory: .transportOffline,
            )),
            .retryScheduled(.init(
                source: .readsb,
                requestCount: 5,
                httpStatus: nil,
                decodedAircraftCount: 11,
                backoffSeconds: 10,
                failureCategory: .transportOffline,
            )),
            .pollingStopped(.init(
                source: .readsb,
                requestCount: 5,
                decodedAircraftCount: 11,
            )),
        ]
        let system = Periscope(
            configuration: .init(
                recentBufferCapacity: 20,
                pendingBufferCapacity: 20,
                liveBufferCapacity: 20,
                flushThreshold: .error,
                redact: nil,
            ),
            sinks: [],
        )
        let logger = PeriscopeAircraftPollingLogger(
            log: Log<ThrowRootLog>(system: system)(AircraftPollingLog.self),
        )

        for event in semanticEvents {
            logger.record(event)
        }

        let records = system.recentRecords()
        #expect(records.map { type(of: $0.event).eventName } == [
            AircraftPollingLog.SourceActivated.eventName,
            AircraftPollingLog.ReceiverMetadataFallback.eventName,
            AircraftPollingLog.RequestSucceeded.eventName,
            AircraftPollingLog.PartialSchemaDrift.eventName,
            AircraftPollingLog.RequestFailed.eventName,
            AircraftPollingLog.RetryScheduled.eventName,
            AircraftPollingLog.PollingStopped.eventName,
        ])

        let activated = try #require(records[0].event as? AircraftPollingLog.SourceActivated)
        #expect(try roundTrip(activated).source == .adsbLol)

        let fallback = try #require(
            records[1].event as? AircraftPollingLog.ReceiverMetadataFallback,
        )
        let decodedFallback = try roundTrip(fallback)
        #expect(decodedFallback.source == .readsb)
        #expect(decodedFallback.failureCategory == .transportOffline)

        let succeeded = try #require(records[2].event as? AircraftPollingLog.RequestSucceeded)
        let decodedSuccess = try roundTrip(succeeded)
        #expect(decodedSuccess.requestCount == 4)
        #expect(decodedSuccess.httpStatus == 206)
        #expect(decodedSuccess.decodedAircraftCount == 12)

        let drift = try #require(records[3].event as? AircraftPollingLog.PartialSchemaDrift)
        let decodedDrift = try roundTrip(drift)
        #expect(decodedDrift.source == .adsbLol)
        #expect(decodedDrift.malformedRecordCount == 2)
        #expect(decodedDrift.missingPositionRecordCount == 3)
        #expect(drift.classifiedFields == [
            .shareable(
                key: LogFieldKey("source"),
                kind: .category,
                value: .string("adsb-lol"),
            ),
            .restricted(key: LogFieldKey("request_count"), kind: .count),
            .restricted(key: LogFieldKey("http_status"), kind: .technicalState),
            .restricted(key: LogFieldKey("decoded_aircraft_count"), kind: .count),
            .shareable(
                key: LogFieldKey("malformed_record_count"),
                kind: .count,
                value: .int(2),
            ),
            .shareable(
                key: LogFieldKey("missing_position_record_count"),
                kind: .count,
                value: .int(3),
            ),
        ])

        let failed = try #require(records[4].event as? AircraftPollingLog.RequestFailed)
        let decodedFailure = try roundTrip(failed)
        #expect(decodedFailure.source == .readsb)
        #expect(decodedFailure.failureCategory == .transportOffline)

        let retry = try #require(records[5].event as? AircraftPollingLog.RetryScheduled)
        let decodedRetry = try roundTrip(retry)
        #expect(decodedRetry.decodedAircraftCount == 11)
        #expect(decodedRetry.backoffSeconds == 10)

        let stopped = try #require(records[6].event as? AircraftPollingLog.PollingStopped)
        let decodedStop = try roundTrip(stopped)
        #expect(decodedStop.requestCount == 5)
        #expect(decodedStop.decodedAircraftCount == 11)
    }

    @Test func geographyFailureIsRedactedAndConcrete() throws {
        #expect(GeographyLogEvent.FailureCategory.allCases.count == 3)
        let event = GeographyLog.LoadFailed(
            failureCategory: .restricted(.category, .invalidArchive),
        )

        #expect(GeographyLog.LoadFailed.eventName == "GeographyLogEvent.load-failed")
        #expect(event.message == "Bundled geography load failed: invalid-archive")
        #expect(event.classifiedFields == [
            .restricted(key: LogFieldKey("failure_category"), kind: .category),
        ])
        #expect(try roundTrip(event).failureCategory == .invalidArchive)
    }

    @Test func routeOutcomesAreClosedAndCarryNoRouteValues() throws {
        #expect(FlightRouteLogEvent.Outcome.allCases.count == 4)
        let event = FlightRouteLog.EnrichmentFinished(
            outcome: .shared(.category, .transportFailed),
        )

        #expect(
            FlightRouteLog.EnrichmentFinished.eventName ==
                "FlightRouteLogEvent.enrichment-finished",
        )
        #expect(event.message == "Flight route enrichment transport-failed")
        #expect(event.classifiedFields == [
            .shareable(
                key: LogFieldKey("outcome"),
                kind: .category,
                value: .string("transport-failed"),
            ),
        ])
        #expect(try roundTrip(event).outcome == .transportFailed)
    }

    @Test func projectionMotionContainsOnlyRestrictedAggregateValues() throws {
        let event = ProjectionMotionLog.Aggregate(
            framesPerSecond: .restricted(.domainValue, 29.8),
            aircraftCount: .restricted(.count, 42),
            usableHorizontalMotionPercent: .restricted(.domainValue, 95),
            positionDerivedMotionPercent: .restricted(.domainValue, 5),
            meanSampleAgeSeconds: .restricted(.duration, 3),
            meanProjectedSpeedPerSecond: .restricted(.domainValue, 0.001),
            meanCorrectionDistance: .restricted(.domainValue, 0.002),
            previousSnapshotRetainedPercent: .restricted(.domainValue, 80),
        )

        #expect(
            ProjectionMotionLog.Aggregate.eventName ==
                "ProjectionMotionLogEvent.aggregate",
        )
        #expect(event.message == "Projection motion aggregate")
        #expect(event.classifiedFields == [
            .restricted(key: LogFieldKey("frames_per_second"), kind: .domainValue),
            .restricted(key: LogFieldKey("aircraft_count"), kind: .count),
            .restricted(
                key: LogFieldKey("usable_horizontal_motion_percent"),
                kind: .domainValue,
            ),
            .restricted(
                key: LogFieldKey("position_derived_motion_percent"),
                kind: .domainValue,
            ),
            .restricted(key: LogFieldKey("mean_sample_age_seconds"), kind: .duration),
            .restricted(
                key: LogFieldKey("mean_projected_speed_per_second"),
                kind: .domainValue,
            ),
            .restricted(
                key: LogFieldKey("mean_correction_distance"),
                kind: .domainValue,
            ),
            .restricted(
                key: LogFieldKey("previous_snapshot_retained_percent"),
                kind: .domainValue,
            ),
        ])
        #expect(try roundTrip(event).aircraftCount == 42)
    }

    private func roundTrip<Event: LogEvent>(_ event: Event) throws -> Event {
        try JSONDecoder().decode(Event.self, from: JSONEncoder().encode(event))
    }
}
