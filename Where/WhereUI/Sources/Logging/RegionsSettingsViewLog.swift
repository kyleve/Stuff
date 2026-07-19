import PeriscopeCore

/// Structured events for `RegionsSettingsView`, the post-onboarding primary-region
/// editor. Both failures leave an honest fallback (an empty picker / staying
/// open) rather than stranding the user, so they log at `.warning`.
enum RegionsSettingsViewLog: LogEvent {
    case primaryRegionsLoadFailed(description: String)
    case primaryRegionsSaveFailed(description: String)

    static let eventName = "RegionsSettings"

    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case let .primaryRegionsLoadFailed(description):
                "Failed to load primary regions for editing: \(description)"
            case let .primaryRegionsSaveFailed(description):
                "Failed to save primary region edits: \(description)"
        }
    }
}
