import PeriscopeCore

/// Structured events for `RegionAttribution`, the live attributor rebuild that
/// tracks the user's tracked-region set. A failed read leaves the prior
/// attributor in place, so it's degraded-but-handled (`.warning`).
enum RegionAttributionLog: LogEvent {
    /// Names the rebuild span. Only an actual change is spanned — reconciling an
    /// unchanged tracked set is a fetch and a set compare, and it runs on every
    /// store commit, so spanning it would bury the rebuilds it exists to show.
    enum SpanName: Hashable {
        case rebuild
    }

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
