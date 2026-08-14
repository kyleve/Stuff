import PeriscopeCore

/// Structured events for `WhereSession`, the always-on tracking/authorization
/// coordinator. Degraded-but-handled authorization states log at `.warning`;
/// successful lifecycle transitions at `.info`.
enum WhereSessionLog: LogEvent {
    private enum RemoteKind: String, CaseIterable {
        case whenInUseOnly = "when-in-use-only"
        case locationAccessDenied = "location-access-denied"
        case backgroundTrackingStarted = "background-tracking-started"
        case backgroundTrackingStopped = "background-tracking-stopped"
        case permissionGranted = "permission-granted"
        case trackingEnabled = "tracking-enabled"
        case stoppedBackgroundTracking = "stopped-background-tracking"
        case recordingReconcileFailed = "recording-reconcile-failed"
        case remindersUnauthorized = "reminders-unauthorized"
        case summaryUnauthorized = "summary-unauthorized"
        case issueAlertsUnauthorized = "issue-alerts-unauthorized"
        case regionStylesLoadFailed = "region-styles-load-failed"
        case erasedSession = "erased-session"
    }

    /// Names the coordinator's timed span.
    ///
    /// Only the *composed* foreground pass is timed. Each individual step
    /// (`syncAuthorization`, `applyReminderConfiguration`, …) delegates straight
    /// to a `WhereCore` collaborator that spans itself, and the launch measures
    /// the same steps individually; a second span per step would double every
    /// reading without adding a fact.
    enum SpanName: Hashable {
        /// Everything the coordinator re-runs when the app returns to the
        /// foreground — the wall-clock cost of a resume, from the user's side.
        case foregroundRefresh
    }

    case whenInUseOnly
    case locationAccessDenied(status: String)
    case backgroundTrackingStarted
    case backgroundTrackingStopped
    case permissionGranted(status: String)
    case trackingEnabled
    case stoppedBackgroundTracking
    case recordingReconcileFailed(description: String)
    case remindersUnauthorized
    case summaryUnauthorized
    case issueAlertsUnauthorized
    case regionStylesLoadFailed(description: String)
    case erasedSession

    static let eventName = "WhereSession"

    var level: LogLevel {
        switch self {
            case .whenInUseOnly, .locationAccessDenied, .remindersUnauthorized,
                 .summaryUnauthorized, .issueAlertsUnauthorized, .regionStylesLoadFailed,
                 .recordingReconcileFailed:
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
            case let .recordingReconcileFailed(description):
                "Failed to reconcile device recording policy: \(description)"
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

    var remoteFields: [RemoteLogField] {
        [RemoteLogField.eventKind(remoteKind)]
    }

    private var remoteKind: RemoteKind {
        switch self {
            case .whenInUseOnly: .whenInUseOnly
            case .locationAccessDenied: .locationAccessDenied
            case .backgroundTrackingStarted: .backgroundTrackingStarted
            case .backgroundTrackingStopped: .backgroundTrackingStopped
            case .permissionGranted: .permissionGranted
            case .trackingEnabled: .trackingEnabled
            case .stoppedBackgroundTracking: .stoppedBackgroundTracking
            case .recordingReconcileFailed: .recordingReconcileFailed
            case .remindersUnauthorized: .remindersUnauthorized
            case .summaryUnauthorized: .summaryUnauthorized
            case .issueAlertsUnauthorized: .issueAlertsUnauthorized
            case .regionStylesLoadFailed: .regionStylesLoadFailed
            case .erasedSession: .erasedSession
        }
    }
}
