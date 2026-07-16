import PeriscopeCore

/// Structured events for `LocationIngestor`'s GPS lifecycle, one-shot capture,
/// and the durable retry queue. Persist failures carry the offending sample id
/// on `externalID` so the tooling can trace one sample across retries.
enum LocationIngestorLog: LogEvent {
    case monitoringStarted
    case monitoringStopped
    case restoredBacklog(count: Int)
    case quiesced
    case todayIntervalUnavailable
    case foregroundCaptureReadFailed(description: String)
    case capturedForegroundFix
    case persistFailed(sampleID: String, description: String)
    case retryQueueAtCapacity(capacity: Int)
    case retryStillFailing(sampleID: String, description: String)
    case drainedBacklog(sampleCount: Int, dayCount: Int)

    static let eventName = "LocationIngestor"

    var level: LogLevel {
        switch self {
            case .monitoringStarted, .monitoringStopped, .restoredBacklog, .quiesced,
                 .capturedForegroundFix, .drainedBacklog:
                .info
            case .todayIntervalUnavailable, .foregroundCaptureReadFailed, .retryQueueAtCapacity:
                .warning
            case .persistFailed, .retryStillFailing:
                .error
        }
    }

    var message: String {
        switch self {
            case .monitoringStarted:
                "GPS monitoring started"
            case .monitoringStopped:
                "GPS monitoring stopped"
            case let .restoredBacklog(count):
                "Restored \(count) sample(s) from durable retry backlog"
            case .quiesced:
                "GPS ingestion quiesced; retry backlog cleared"
            case .todayIntervalUnavailable:
                "Could not compute today's interval for foreground capture"
            case let .foregroundCaptureReadFailed(description):
                "Skipping foreground capture; could not read today's samples: \(description)"
            case .capturedForegroundFix:
                "Captured one-shot foreground location for today"
            case let .persistFailed(sampleID, description):
                "Failed to persist GPS sample \(sampleID): \(description)"
            case let .retryQueueAtCapacity(capacity):
                "Retry queue at capacity (\(capacity)); dropping oldest queued GPS sample"
            case let .retryStillFailing(sampleID, description):
                "Retry still failing for GPS sample \(sampleID): \(description)"
            case let .drainedBacklog(sampleCount, dayCount):
                "Drained retry backlog: persisted \(sampleCount) sample(s) across \(dayCount) day(s)"
        }
    }

    var externalID: String? {
        switch self {
            case let .persistFailed(sampleID, _), let .retryStillFailing(sampleID, _):
                WhereStoreID.sample(sampleID)
            case .monitoringStarted, .monitoringStopped, .restoredBacklog, .quiesced,
                 .todayIntervalUnavailable, .foregroundCaptureReadFailed, .capturedForegroundFix,
                 .retryQueueAtCapacity, .drainedBacklog:
                nil
        }
    }
}
