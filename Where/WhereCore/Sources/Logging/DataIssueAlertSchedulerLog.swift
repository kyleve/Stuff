import PeriscopeCore

/// Structured events for `DataIssueAlertScheduler`.
@LogScope("DataIssueAlertScheduler")
enum DataIssueAlertSchedulerLog {
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
        message: "Issue alerts enabled but notification authorization not granted; alert disabled",
    )
    struct AuthorizationNotGranted {}

    @LogEvent(
        "authorization-unknown",
        level: .warning,
        message: "Issue alerts enabled but notification authorization status is unknown; alert disabled",
    )
    struct AuthorizationUnknown {}

    @LogEvent("scheduled", level: .info)
    struct Scheduled {
        @LogField("time", exposure: .restricted, kind: .dateTime)
        var time: String

        var message: String {
            "Scheduled issue alert at \(time)"
        }
    }

    @LogEvent("schedule-failed", level: .error)
    struct ScheduleFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Failed to schedule issue alert: \(description)"
        }
    }
}
