import PeriscopeCore

/// Structured events for `DataIssueAlertScheduler`.
@LogScope("DataIssueAlertScheduler")
enum DataIssueAlertSchedulerLog {
    @LogEvent("authorization-request-failed", level: .error, version: 2)
    struct AuthorizationRequestFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Notification authorization request failed: \(error.description)"
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
        @LogField(exposure: .restricted, kind: .dateTime)
        var time: String

        var message: String {
            "Scheduled issue alert at \(time)"
        }
    }

    @LogEvent("schedule-failed", level: .error, version: 2)
    struct ScheduleFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Failed to schedule issue alert: \(error.description)"
        }
    }
}
