import PeriscopeCore

/// Structured events for `RegionAttribution`, the live attributor rebuild that
/// tracks the user's tracked-region set. A failed read leaves the prior
/// attributor in place, so it's degraded-but-handled (`.warning`).
enum RegionAttributionLog: LogEvent {
    case trackedRegionsReadFailed(description: String)

    static let eventName = "RegionAttribution"

    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case let .trackedRegionsReadFailed(description):
                "Failed to read tracked regions for attributor rebuild: \(description)"
        }
    }
}
