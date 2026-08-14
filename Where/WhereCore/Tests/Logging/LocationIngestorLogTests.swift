import PeriscopeCore
import Testing
@testable import WhereCore

struct LocationIngestorLogTests {
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
            description: .restricted(.errorDetails, "private error"),
        )
        #expect(event.classifiedFields == [
            .restricted(key: LogFieldKey("sample_id"), kind: .identifier),
            .restricted(key: LogFieldKey("description"), kind: .errorDetails),
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
