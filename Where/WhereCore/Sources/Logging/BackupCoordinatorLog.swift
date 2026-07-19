import PeriscopeCore

/// Structured events for `BackupCoordinator`. Failing to clear a previous export
/// staging directory is degraded-but-handled housekeeping, so it logs at
/// `.warning`.
enum BackupCoordinatorLog: LogEvent {
    case removePreviousExportFailed(description: String)

    static let eventName = "BackupCoordinator"

    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case let .removePreviousExportFailed(description):
                "Failed to remove previous backup export directory: \(description)"
        }
    }
}
