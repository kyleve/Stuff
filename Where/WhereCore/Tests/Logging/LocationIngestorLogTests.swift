import Foundation
import PeriscopeCore
import Testing
@testable import WhereCore

struct LocationIngestorLogTests {
    @Test func errorEventsPreserveMessagesSeverityAndExternalIDs() throws {
        let original = NSError(
            domain: "PrivateLocation",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "unavailable"],
        )
        try verifyLocationErrorEvent(
            LocationIngestorLog.ForegroundCaptureReadFailed(error: .restricted(
                .errorDetails,
                original,
            )),
            name: "LocationIngestor.foreground-capture-read-failed",
            message: "Skipping foreground capture; could not read today's samples: unavailable",
            level: .warning,
            original: original,
            externalID: nil,
        )
        try verifyLocationErrorEvent(
            LocationIngestorLog.PersistFailed(
                sampleID: .restricted(.identifier, "abc"),
                error: .restricted(.errorDetails, original),
            ),
            name: "LocationIngestor.persist-failed",
            message: "Failed to persist GPS sample abc: unavailable",
            level: .error,
            original: original,
            externalID: WhereStoreID.sample("abc"),
        )
        try verifyLocationErrorEvent(
            LocationIngestorLog.RetryBacklogPersistenceFailed(error: .restricted(
                .errorDetails,
                original,
            )),
            name: "LocationIngestor.retry-backlog-persistence-failed",
            message: "Failed to durably persist the GPS retry backlog; stopping recording: unavailable",
            level: .error,
            original: original,
            externalID: nil,
        )
        try verifyLocationErrorEvent(
            LocationIngestorLog.RetryStillFailing(
                sampleID: .restricted(.identifier, "abc"),
                error: .restricted(.errorDetails, original),
            ),
            name: "LocationIngestor.retry-still-failing",
            message: "Retry still failing for GPS sample abc: unavailable",
            level: .error,
            original: original,
            externalID: WhereStoreID.sample("abc"),
        )
    }

    @Test func everyEventHasAStableDistinctName() {
        let names = [
            LocationIngestorLog.MonitoringStarted.eventName,
            LocationIngestorLog.MonitoringStopped.eventName,
            LocationIngestorLog.RestoredBacklog.eventName,
            LocationIngestorLog.Quiesced.eventName,
            LocationIngestorLog.TodayIntervalUnavailable.eventName,
            LocationIngestorLog.ForegroundCaptureReadFailed.eventName,
            LocationIngestorLog.CapturedForegroundFix.eventName,
            LocationIngestorLog.PersistFailed.eventName,
            LocationIngestorLog.RetryBacklogPersistenceFailed.eventName,
            LocationIngestorLog.RetryQueueAtCapacity.eventName,
            LocationIngestorLog.RetryStillFailing.eventName,
            LocationIngestorLog.DrainedBacklog.eventName,
        ]

        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { $0.hasPrefix("LocationIngestor.") })
    }

    @Test func projectionPreservesTheExistingRemoteBoundary() {
        let event = LocationIngestorLog.PersistFailed(
            sampleID: .restricted(.identifier, "private id"),
            error: .restricted(.errorDetails, NSError(domain: "Private", code: 1)),
        )
        #expect(event.classifiedFields == [
            .restricted(key: LogFieldKey("sample_id"), kind: .identifier),
            .restricted(key: LogFieldKey("error"), kind: .errorDetails),
        ])

        let drained = LocationIngestorLog.DrainedBacklog(
            sampleCount: .shared(.count, 3),
            dayCount: .shared(.count, 2),
        )
        #expect(drained.classifiedFields == [
            .shareable(key: LogFieldKey("sample_count"), kind: .count, value: .int(3)),
            .shareable(key: LogFieldKey("day_count"), kind: .count, value: .int(2)),
        ])
    }
}
