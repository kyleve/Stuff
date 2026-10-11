import PeriscopeCore

/// Offline use preserves verified authority without hiding the failed refresh.
enum RecordingCoordinationLog: LogEvent {
    case usingCachedAuthority
    static let eventName = "RecordingCoordination"
    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case .usingCachedAuthority: "Authority refresh is unavailable; using the last verified state."
        }
    }
}
