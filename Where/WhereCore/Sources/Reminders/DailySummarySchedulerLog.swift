import PeriscopeCore

/// Structured events for `DailySummaryScheduler` — authorization outcomes and
/// the scheduling of the daily recap notification.
enum DailySummarySchedulerLog: LogEvent {
    case authorizationRequestFailed(description: String)
    case authorizationNotGranted
    case authorizationUnknown
    case scheduled(time: String)
    case scheduleFailed(description: String)

    static let eventName = "DailySummaryScheduler"

    var level: LogLevel {
        switch self {
            case .authorizationRequestFailed, .scheduleFailed:
                .error
            case .authorizationNotGranted, .authorizationUnknown:
                .warning
            case .scheduled:
                .info
        }
    }

    var message: String {
        switch self {
            case let .authorizationRequestFailed(description):
                "Notification authorization request failed: \(description)"
            case .authorizationNotGranted:
                "Daily summary enabled but notification authorization not granted; summary disabled"
            case .authorizationUnknown:
                "Daily summary enabled but notification authorization status is unknown; summary disabled"
            case let .scheduled(time):
                "Scheduled daily summary at \(time)"
            case let .scheduleFailed(description):
                "Failed to schedule daily summary: \(description)"
        }
    }
}
