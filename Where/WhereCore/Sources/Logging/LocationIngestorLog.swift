import PeriscopeCore

/// Structured events for `LocationIngestor`'s GPS lifecycle, one-shot capture,
/// and the durable retry queue. Persist failures carry the offending sample id
/// on `externalID` so the tooling can trace one sample across retries.
enum LocationIngestorLog: LogEvent {
    private enum RemoteKind: String, CaseIterable {
        case monitoringStarted = "monitoring-started"
        case monitoringStopped = "monitoring-stopped"
        case restoredBacklog = "restored-backlog"
        case quiesced
        case todayIntervalUnavailable = "today-interval-unavailable"
        case foregroundCaptureReadFailed = "foreground-capture-read-failed"
        case capturedForegroundFix = "captured-foreground-fix"
        case persistFailed = "persist-failed"
        case retryBacklogPersistenceFailed = "retry-backlog-persistence-failed"
        case retryQueueAtCapacity = "retry-queue-at-capacity"
        case retryStillFailing = "retry-still-failing"
        case drainedBacklog = "drained-backlog"
    }

    /// Names the ingestor's timed spans.
    ///
    /// The single-sample commit isn't here — `SwiftDataStore` already spans every
    /// transaction, and a second span around the same `perform` would only
    /// restate it. What's spanned instead is everything *around* the write that
    /// nothing else measures: waiting on CoreLocation, working through a
    /// backlog, and the reconcile fan-out a persisted sample triggers.
    enum SpanName: Hashable {
        /// Waiting on the one-shot GPS fix behind `captureTodayIfNeeded(now:)`.
        /// The slowest thing the ingestor does by an order of magnitude, and it
        /// runs on a launch step's tail, so it's budgeted at CoreLocation's own
        /// rough ceiling.
        case acquireFix
        /// Re-persisting a retry backlog, one transaction per queued sample.
        /// Only a non-empty drain is spanned.
        case drainBacklog
        /// The post-persist reconcile fan-out (badge/reminders, issue alerts,
        /// widget snapshot). Runs on the hot GPS path, so its cost is the
        /// ingestor's, not the caller's.
        case postPersist
    }

    case monitoringStarted
    case monitoringStopped
    case restoredBacklog(count: Int)
    case quiesced
    case todayIntervalUnavailable
    case foregroundCaptureReadFailed(description: String)
    case capturedForegroundFix
    case persistFailed(sampleID: String, description: String)
    case retryBacklogPersistenceFailed(description: String)
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
            case .persistFailed, .retryBacklogPersistenceFailed, .retryStillFailing:
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
            case let .retryBacklogPersistenceFailed(description):
                "Failed to durably persist the GPS retry backlog; stopping recording: \(description)"
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
                 .retryBacklogPersistenceFailed, .retryQueueAtCapacity, .drainedBacklog:
                nil
        }
    }

    var remoteFields: [RemoteLogField] {
        var fields = [RemoteLogField.eventKind(remoteKind)]
        switch self {
            case let .restoredBacklog(count):
                fields.append(RemoteLogField(
                    key: RemoteLogFieldKey("backlog_count"),
                    value: .count(count),
                ))
            case let .retryQueueAtCapacity(capacity):
                fields.append(RemoteLogField(
                    key: RemoteLogFieldKey("capacity"),
                    value: .count(capacity),
                ))
            case let .drainedBacklog(sampleCount, dayCount):
                fields.append(contentsOf: [
                    RemoteLogField(
                        key: RemoteLogFieldKey("sample_count"),
                        value: .count(sampleCount),
                    ),
                    RemoteLogField(key: RemoteLogFieldKey("day_count"), value: .count(dayCount)),
                ])
            case .monitoringStarted, .monitoringStopped, .quiesced, .todayIntervalUnavailable,
                 .foregroundCaptureReadFailed, .capturedForegroundFix, .persistFailed,
                 .retryBacklogPersistenceFailed, .retryStillFailing:
                break
        }
        return fields
    }

    private var remoteKind: RemoteKind {
        switch self {
            case .monitoringStarted: .monitoringStarted
            case .monitoringStopped: .monitoringStopped
            case .restoredBacklog: .restoredBacklog
            case .quiesced: .quiesced
            case .todayIntervalUnavailable: .todayIntervalUnavailable
            case .foregroundCaptureReadFailed: .foregroundCaptureReadFailed
            case .capturedForegroundFix: .capturedForegroundFix
            case .persistFailed: .persistFailed
            case .retryBacklogPersistenceFailed: .retryBacklogPersistenceFailed
            case .retryQueueAtCapacity: .retryQueueAtCapacity
            case .retryStillFailing: .retryStillFailing
            case .drainedBacklog: .drainedBacklog
        }
    }
}
