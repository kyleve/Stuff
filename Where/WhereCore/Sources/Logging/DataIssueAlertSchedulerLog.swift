import PeriscopeCore

/// Structured events for `DataIssueAlertScheduler` — authorization outcomes and
/// the scheduling of the "issues to resolve" notification.
enum DataIssueAlertSchedulerLog: LogEvent {
    case authorizationRequestFailed(description: String)
    case authorizationNotGranted
    case authorizationUnknown
    case scheduled(time: String)
    case scheduleFailed(description: String)

    static let eventName = "DataIssueAlertScheduler"

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
                "Issue alerts enabled but notification authorization not granted; alert disabled"
            case .authorizationUnknown:
                "Issue alerts enabled but notification authorization status is unknown; alert disabled"
            case let .scheduled(time):
                "Scheduled issue alert at \(time)"
            case let .scheduleFailed(description):
                "Failed to schedule issue alert: \(description)"
        }
    }
}
