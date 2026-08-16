import PeriscopeCore
import Testing
@testable import WhereCore

struct LocationIngestorLogTests {
    @Test func everyEventCaseExportsADistinctSafeKind() {
        let events: [LocationIngestorLog] = [
            .monitoringStarted,
            .monitoringStopped,
            .restoredBacklog(count: 2),
            .quiesced,
            .todayIntervalUnavailable,
            .foregroundCaptureReadFailed(description: "private error"),
            .capturedForegroundFix,
            .persistFailed(sampleID: "private id", description: "private error"),
            .retryBacklogPersistenceFailed(description: "private error"),
            .retryQueueAtCapacity(capacity: 20),
            .retryStillFailing(sampleID: "private id", description: "private error"),
            .drainedBacklog(sampleCount: 3, dayCount: 2),
        ]

        let kinds = events.compactMap(remoteKind)
        #expect(kinds.count == events.count)
        #expect(Set(kinds).count == events.count)
        #expect(kinds.contains("private id") == false)
        #expect(kinds.contains("private error") == false)
    }

    private func remoteKind(_ event: LocationIngestorLog) -> String? {
        guard let field = event.remoteFields.first,
              field.key == RemoteLogFieldKey("kind"),
              case let .category(category) = field.value
        else { return nil }
        return category.rawValue
    }
}
