import PeriscopeCore

/// Structured events for `DailySummaryScheduler`.
@LogScope("DailySummaryScheduler")
enum DailySummarySchedulerLog {
    @LogEvent("authorization-request-failed", level: .error)
    struct AuthorizationRequestFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Notification authorization request failed: \(description)"
        }
    }

    @LogEvent(
        "authorization-not-granted",
        level: .warning,
        message: "Daily summary enabled but notification authorization not granted; summary disabled",
    )
    struct AuthorizationNotGranted {}

    @LogEvent(
        "authorization-unknown",
        level: .warning,
        message: "Daily summary enabled but notification authorization status is unknown; summary disabled",
    )
    struct AuthorizationUnknown {}

    @LogEvent("scheduled", level: .info)
    struct Scheduled {
        @LogField("time", exposure: .restricted, kind: .dateTime)
        var time: String

        var message: String {
            "Scheduled daily summary at \(time)"
        }
    }

    @LogEvent("schedule-failed", level: .error)
    struct ScheduleFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Failed to schedule daily summary: \(description)"
        }
    }
}
