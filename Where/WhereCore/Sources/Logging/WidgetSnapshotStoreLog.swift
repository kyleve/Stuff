import PeriscopeCore

/// Structured events for `WidgetSnapshotStore`'s read path.
///
/// `read()` answers `nil` for two very different situations — nothing published
/// yet (a fresh install, and the widget's normal placeholder cue) and a file that
/// exists but won't decode (a truncated write, a stale format). Only the second
/// is a failure, so only the second logs: a warning, because the widget still has
/// an honest empty state to render and the next publish overwrites the bad file.
enum WidgetSnapshotStoreLog: LogEvent {
    /// The snapshot file exists but couldn't be decoded, so the widget renders
    /// its empty state as though nothing had been published.
    case unreadableSnapshot(description: String)

    static let eventName = "WidgetSnapshotStore"

    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case let .unreadableSnapshot(description):
                "Discarded an unreadable widget snapshot file: \(description)"
        }
    }
}
