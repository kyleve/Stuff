import PeriscopeCore

/// Structured events for `FileLocationOutbox`, the durable mirror of the GPS
/// retry queue. A missing Application Support directory is degraded-but-handled
/// (`.warning`); read/write failures are surfaced as `.error`.
enum LocationOutboxLog: LogEvent {
    case noApplicationSupport
    case droppedUnreadableBacklog(description: String)
    case persistBacklogFailed(description: String)

    static let eventName = "LocationOutbox"

    var level: LogLevel {
        switch self {
            case .noApplicationSupport: .warning
            case .droppedUnreadableBacklog, .persistBacklogFailed: .error
        }
    }

    var message: String {
        switch self {
            case .noApplicationSupport:
                "No Application Support directory; using in-memory retry queue (backlog won't survive relaunch)"
            case let .droppedUnreadableBacklog(description):
                "Dropping unreadable location retry backlog: \(description)"
            case let .persistBacklogFailed(description):
                "Failed to persist location retry backlog: \(description)"
        }
    }
}
