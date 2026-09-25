import PeriscopeCore

/// Structured events for `LocationIngestor`'s GPS lifecycle and durable retry queue.
@LogScope("LocationIngestor")
enum LocationIngestorLog {
    enum SpanName: Hashable {
        case acquireFix
        case drainBacklog
        case postPersist
    }

    @LogEvent("monitoring-started", message: "GPS monitoring started")
    struct MonitoringStarted {}

    @LogEvent("monitoring-stopped", message: "GPS monitoring stopped")
    struct MonitoringStopped {}

    @LogEvent("restored-backlog")
    struct RestoredBacklog {
        @LogField("backlog_count", exposure: .shareable, kind: .count)
        var count: Int

        var message: String {
            "Restored \(count) sample(s) from durable retry backlog"
        }
    }

    @LogEvent("quiesced", message: "GPS ingestion quiesced; retry backlog cleared")
    struct Quiesced {}

    @LogEvent(
        "today-interval-unavailable",
        level: .warning,
        message: "Could not compute today's interval for foreground capture",
    )
    struct TodayIntervalUnavailable {}

    @LogEvent("foreground-capture-read-failed", level: .warning)
    struct ForegroundCaptureReadFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Skipping foreground capture; could not read today's samples: \(description)"
        }
    }

    @LogEvent(
        "captured-foreground-fix",
        message: "Captured one-shot foreground location for today",
    )
    struct CapturedForegroundFix {}

    @LogEvent("persist-failed", level: .error)
    struct PersistFailed {
        @LogField("sample_id", exposure: .restricted, kind: .identifier)
        var sampleID: String

        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Failed to persist GPS sample \(sampleID): \(description)"
        }

        var externalID: String? {
            WhereStoreID.sample(sampleID)
        }
    }

    @LogEvent("retry-backlog-persistence-failed", level: .error)
    struct RetryBacklogPersistenceFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Failed to durably persist the GPS retry backlog; stopping recording: \(description)"
        }
    }

    @LogEvent("retry-queue-at-capacity", level: .warning)
    struct RetryQueueAtCapacity {
        @LogField("capacity", exposure: .shareable, kind: .count)
        var capacity: Int

        var message: String {
            "Retry queue at capacity (\(capacity)); dropping oldest queued GPS sample"
        }
    }

    @LogEvent("retry-still-failing", level: .error)
    struct RetryStillFailing {
        @LogField("sample_id", exposure: .restricted, kind: .identifier)
        var sampleID: String

        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Retry still failing for GPS sample \(sampleID): \(description)"
        }

        var externalID: String? {
            WhereStoreID.sample(sampleID)
        }
    }

    @LogEvent("drained-backlog")
    struct DrainedBacklog {
        @LogField("sample_count", exposure: .shareable, kind: .count)
        var sampleCount: Int

        @LogField("day_count", exposure: .shareable, kind: .count)
        var dayCount: Int

        var message: String {
            "Drained retry backlog: persisted \(sampleCount) sample(s) across \(dayCount) day(s)"
        }
    }
}
