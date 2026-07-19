import PeriscopeCore

/// Structured events for the Where App Intents surface — Spotlight indexing of
/// the tracked regions and the recent-activity summary intent. These run in the
/// app/intents process, which keeps `Periscope.shared` OSLog-only (no
/// persistent store of its own).
enum WhereIntentsLog: LogEvent {
    /// The tracked regions were indexed into Spotlight.
    case spotlightIndexed(regionCount: Int)
    /// Indexing the tracked regions into Spotlight failed
    /// (degraded-but-handled: search integration is a nicety).
    case spotlightIndexFailed(description: String)
    /// The recent-activity summary couldn't be produced (e.g. Apple
    /// Intelligence is off or the model is warming).
    case recentActivityUnavailable(reason: String)

    static let eventName = "WhereIntents"

    var level: LogLevel {
        switch self {
            case .spotlightIndexed:
                .info
            case .spotlightIndexFailed, .recentActivityUnavailable:
                .warning
        }
    }

    var message: String {
        switch self {
            case let .spotlightIndexed(regionCount):
                "Indexed \(regionCount) region(s) for Spotlight"
            case let .spotlightIndexFailed(description):
                "Failed to index regions for Spotlight: \(description)"
            case let .recentActivityUnavailable(reason):
                "Recent-activity summary unavailable: \(reason)"
        }
    }
}
