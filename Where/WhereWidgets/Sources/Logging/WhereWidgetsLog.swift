import PeriscopeCore

/// Structured events for the Where widget timeline provider — a separate
/// WidgetKit process, so `Periscope.shared` stays OSLog-only (no store).
enum WhereWidgetsLog: LogEvent {
    /// No snapshot has been published yet (fresh install, unreadable file); the
    /// provider renders the empty state.
    case noPublishedSnapshot
    /// The shared App Group container couldn't be opened.
    case appGroupUnavailable(description: String)

    static let eventName = "WhereWidgets"

    var level: LogLevel {
        switch self {
            case .noPublishedSnapshot:
                .warning
            case .appGroupUnavailable:
                .error
        }
    }

    var message: String {
        switch self {
            case .noPublishedSnapshot:
                "No published widget snapshot; rendering empty state"
            case let .appGroupUnavailable(description):
                "Widget App Group unavailable: \(description)"
        }
    }
}
