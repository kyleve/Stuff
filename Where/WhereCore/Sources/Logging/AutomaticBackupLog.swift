import PeriscopeCore

enum AutomaticBackupLog: LogEvent {
    case iCloudUnavailable
    case iCloudAccessFailed(description: String)
    case ignoredUnrecognizedFile(name: String)
    case cleanupFailed(description: String)

    static let eventName = "AutomaticBackup"

    var level: LogLevel {
        switch self {
            case .iCloudUnavailable, .iCloudAccessFailed, .ignoredUnrecognizedFile,
                 .cleanupFailed:
                .warning
        }
    }

    var message: String {
        switch self {
            case .iCloudUnavailable:
                "iCloud Drive is unavailable; using local backup storage"
            case let .iCloudAccessFailed(description):
                "iCloud backup access failed; using local storage: \(description)"
            case let .ignoredUnrecognizedFile(name):
                "Ignored unrecognized automatic-backup file: \(name)"
            case let .cleanupFailed(description):
                "Automatic-backup staging cleanup failed: \(description)"
        }
    }
}
