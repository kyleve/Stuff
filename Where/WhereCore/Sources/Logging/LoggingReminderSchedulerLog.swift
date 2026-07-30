import PeriscopeCore

/// Structured events for `LoggingReminderScheduler` — authorization outcomes and
/// the reconcile of scheduled/removed reminders + badge.
enum LoggingReminderSchedulerLog: LogEvent {
    /// Names the scheduler's timed span. The sibling summary/issue-alert
    /// schedulers stay unspanned: each is a single add-or-remove, whereas this
    /// one walks the pending *and* delivered sets and can add a week of
    /// requests — several `UNUserNotificationCenter` round-trips, all of them
    /// cross-process.
    enum SpanName: Hashable {
        case reconcileNotifications
    }

    case authorizationRequestFailed(description: String)
    case authorizationNotGranted
    case authorizationUnknown
    case reconciled(scheduled: Int, removed: Int, badge: Int)
    case scheduleFailed(identifier: String, description: String)
    case badgeUpdateFailed(description: String)

    static let eventName = "LoggingReminderScheduler"

    var level: LogLevel {
        switch self {
            case .authorizationRequestFailed, .scheduleFailed, .badgeUpdateFailed:
                .error
            case .authorizationNotGranted, .authorizationUnknown:
                .warning
            case .reconciled:
                .info
        }
    }

    var message: String {
        switch self {
            case let .authorizationRequestFailed(description):
                "Notification authorization request failed: \(description)"
            case .authorizationNotGranted:
                "Logging reminders enabled but notification authorization not granted; reminders disabled"
            case .authorizationUnknown:
                "Logging reminders enabled but notification authorization status is unknown; reminders disabled"
            case let .reconciled(scheduled, removed, badge):
                "Reconciled logging reminders (scheduled \(scheduled), removed \(removed); badge: \(badge))"
            case let .scheduleFailed(identifier, description):
                "Failed to schedule reminder \(identifier): \(description)"
            case let .badgeUpdateFailed(description):
                "Failed to set badge count: \(description)"
        }
    }
}
