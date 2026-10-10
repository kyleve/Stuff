import PeriscopeCore

/// Structured events for `DailySummaryScheduler`.
@LogScope("DailySummaryScheduler")
enum DailySummarySchedulerLog {
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
        @LogField(exposure: .restricted, kind: .dateTime)
        var time: String

        var message: String {
            "Scheduled daily summary at \(time)"
        }
    }

    @LogEvent("schedule-failed", level: .error, version: 2)
    struct ScheduleFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Failed to schedule daily summary: \(error.description)"
        }
    }
}
