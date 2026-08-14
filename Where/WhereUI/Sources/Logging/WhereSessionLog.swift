import PeriscopeCore

/// Structured events and spans for `WhereSession`.
@LogScope("WhereSession")
enum WhereSessionLog {
    enum SpanName: Hashable { case foregroundRefresh }

    @LogEvent(
        "when-in-use-only",
        level: .warning,
        message: "Location authorized for When-In-Use only; background tracking unavailable",
    )
    struct WhenInUseOnly {}

    @LogEvent("location-access-denied", level: .warning)
    struct LocationAccessDenied {
        @LogField("status", exposure: .restricted, kind: .technicalState) var status: String
        var message: String {
            "Location access \(status); background tracking unavailable"
        }
    }

    @LogEvent("background-tracking-started", message: "Background tracking started")
    struct BackgroundTrackingStarted {}

    @LogEvent("background-tracking-stopped", message: "Background tracking stopped")
    struct BackgroundTrackingStopped {}

    @LogEvent("permission-granted")
    struct PermissionGranted {
        @LogField("status", exposure: .restricted, kind: .technicalState) var status: String
        var message: String {
            "Location permission granted (\(status))"
        }
    }

    @LogEvent("tracking-enabled", message: "Tracking enabled with background authorization")
    struct TrackingEnabled {}

    @LogEvent("stopped-background-tracking", message: "Stopped background tracking")
    struct StoppedBackgroundTracking {}

    @LogEvent("recording-reconcile-failed", level: .warning)
    struct RecordingReconcileFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to reconcile device recording policy: \(description)"
        }
    }

    @LogEvent(
        "reminders-unauthorized",
        level: .warning,
        message: "Logging reminders enabled but notifications not authorized",
    )
    struct RemindersUnauthorized {}

    @LogEvent(
        "summary-unauthorized",
        level: .warning,
        message: "Daily summary enabled but notifications not authorized",
    )
    struct SummaryUnauthorized {}

    @LogEvent(
        "issue-alerts-unauthorized",
        level: .warning,
        message: "Issue alerts enabled but notifications not authorized",
    )
    struct IssueAlertsUnauthorized {}

    @LogEvent("region-styles-load-failed", level: .warning)
    struct RegionStylesLoadFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Failed to load region appearances for styling: \(description)"
        }
    }

    @LogEvent("erased-session", message: "Erased session and reset state")
    struct ErasedSession {}
}
