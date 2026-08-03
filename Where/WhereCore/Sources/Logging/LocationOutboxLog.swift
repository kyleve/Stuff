import PeriscopeCore

/// Structured events for `FileLocationOutbox`, the durable mirror of the GPS
/// retry queue. A missing Application Support directory is degraded-but-handled
/// (`.warning`); read/write and backup-exclusion failures are surfaced as
/// `.error`.
enum LocationOutboxLog: LogEvent {
    case noApplicationSupport
    case droppedUnreadableBacklog(description: String)
    case readBacklogFailed(description: String)
    case persistBacklogFailed(description: String)
    case excludeFromBackupFailed(description: String)
    case discardInsecureBacklogFailed(description: String)

    static let eventName = "LocationOutbox"

    var level: LogLevel {
        switch self {
            case .noApplicationSupport: .warning
            case .droppedUnreadableBacklog,
                 .readBacklogFailed,
                 .persistBacklogFailed,
                 .excludeFromBackupFailed,
                 .discardInsecureBacklogFailed: .error
        }
    }

    var message: String {
        switch self {
            case .noApplicationSupport:
                "No Application Support directory; using in-memory retry queue (backlog won't survive relaunch)"
            case let .droppedUnreadableBacklog(description):
                "Dropping unreadable location retry backlog: \(description)"
            case let .readBacklogFailed(description):
                "Failed to read location retry backlog; preserving it for retry: \(description)"
            case let .persistBacklogFailed(description):
                "Failed to persist location retry backlog: \(description)"
            case let .excludeFromBackupFailed(description):
                "Failed to exclude location retry backlog from device backup: \(description)"
            case let .discardInsecureBacklogFailed(description):
                "Failed to discard a backup-eligible location retry backlog: \(description)"
        }
    }
}
