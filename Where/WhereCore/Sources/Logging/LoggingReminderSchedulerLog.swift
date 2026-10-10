import PeriscopeCore

/// Structured events and spans for `LoggingReminderScheduler`.
@LogScope("LoggingReminderScheduler")
enum LoggingReminderSchedulerLog {
    enum SpanName: Hashable {
        case reconcileNotifications
    }

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
        message: "Logging reminders enabled but notification authorization not granted; reminders disabled",
    )
    struct AuthorizationNotGranted {}

    @LogEvent(
        "authorization-unknown",
        level: .warning,
        message: "Logging reminders enabled but notification authorization status is unknown; reminders disabled",
    )
    struct AuthorizationUnknown {}

    @LogEvent("reconciled", level: .info)
    struct Reconciled {
        @LogField("scheduled_count", exposure: .shareable, kind: .count)
        var scheduled: Int
        @LogField("removed_count", exposure: .shareable, kind: .count)
        var removed: Int
        @LogField("badge_count", exposure: .shareable, kind: .count)
        var badge: Int

        var message: String {
            "Reconciled logging reminders (scheduled \(scheduled), removed \(removed); badge: \(badge))"
        }
    }

    @LogEvent("schedule-failed", level: .error, version: 2)
    struct ScheduleFailed {
        @LogField(exposure: .restricted, kind: .identifier)
        var identifier: String
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to schedule reminder \(identifier): \(error.description)"
        }
    }

    @LogEvent("badge-update-failed", level: .error, version: 2)
    struct BadgeUpdateFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Failed to set badge count: \(error.description)"
        }
    }
}
