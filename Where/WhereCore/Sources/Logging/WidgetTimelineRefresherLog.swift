import PeriscopeCore

/// Structured events for `WidgetCenterTimelineRefresher`, which writes the
/// snapshot to the App Group and reloads WidgetKit timelines.
enum WidgetTimelineRefresherLog: LogEvent {
    case wroteSnapshot
    case publishFailed(description: String)

    static let eventName = "WidgetRefresher"

    var level: LogLevel {
        switch self {
            case .wroteSnapshot: .info
            case .publishFailed: .error
        }
    }

    var message: String {
        switch self {
            case .wroteSnapshot:
                "Wrote widget snapshot to App Group; reloading timelines"
            case let .publishFailed(description):
                "Failed to publish widget snapshot: \(description)"
        }
    }
}
