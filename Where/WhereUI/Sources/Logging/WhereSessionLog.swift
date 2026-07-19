import PeriscopeCore

/// Structured events for `WhereSession`, the always-on tracking/authorization
/// coordinator. Degraded-but-handled authorization states log at `.warning`;
/// successful lifecycle transitions at `.info`.
enum WhereSessionLog: LogEvent {
    case whenInUseOnly
    case locationAccessDenied(status: String)
    case backgroundTrackingStarted
    case backgroundTrackingStopped
    case permissionGranted(status: String)
    case trackingEnabled
    case stoppedBackgroundTracking
    case remindersUnauthorized
    case summaryUnauthorized
    case issueAlertsUnauthorized
    case regionStylesLoadFailed(description: String)
    case erasedSession

    static let eventName = "WhereSession"

    var level: LogLevel {
        switch self {
            case .whenInUseOnly, .locationAccessDenied, .remindersUnauthorized,
                 .summaryUnauthorized, .issueAlertsUnauthorized, .regionStylesLoadFailed:
                .warning
            case .backgroundTrackingStarted, .backgroundTrackingStopped, .permissionGranted,
                 .trackingEnabled, .stoppedBackgroundTracking, .erasedSession:
                .info
        }
    }

    var message: String {
        switch self {
            case .whenInUseOnly:
                "Location authorized for When-In-Use only; background tracking unavailable"
            case let .locationAccessDenied(status):
                "Location access \(status); background tracking unavailable"
            case .backgroundTrackingStarted:
                "Background tracking started"
            case .backgroundTrackingStopped:
                "Background tracking stopped"
            case let .permissionGranted(status):
                "Location permission granted (\(status))"
            case .trackingEnabled:
                "Tracking enabled with background authorization"
            case .stoppedBackgroundTracking:
                "Stopped background tracking"
            case .remindersUnauthorized:
                "Logging reminders enabled but notifications not authorized"
            case .summaryUnauthorized:
                "Daily summary enabled but notifications not authorized"
            case .issueAlertsUnauthorized:
                "Issue alerts enabled but notifications not authorized"
            case let .regionStylesLoadFailed(description):
                "Failed to load region appearances for styling: \(description)"
            case .erasedSession:
                "Erased session and reset state"
        }
    }
}
