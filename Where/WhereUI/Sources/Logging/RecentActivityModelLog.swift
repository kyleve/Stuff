import PeriscopeCore

/// Structured events for `RecentActivityModel`. Both an unavailable on-device
/// model and a generation failure leave an honest UI error, so they log at
/// `.warning`.
enum RecentActivityModelLog: LogEvent {
    case summaryUnavailable(reason: String)
    case summaryFailed(description: String)

    static let eventName = "RecentActivityModel"

    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case let .summaryUnavailable(reason):
                "Recent-activity summary unavailable: \(reason)"
            case let .summaryFailed(description):
                "Recent-activity summary failed: \(description)"
        }
    }
}
