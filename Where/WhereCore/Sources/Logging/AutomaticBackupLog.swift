import PeriscopeCore

/// Classified automatic-backup diagnostics. File names and errors stay restricted.
@LogScope("AutomaticBackup")
enum AutomaticBackupLog {
    @LogEvent(
        "icloud-unavailable",
        level: .warning,
        message: "iCloud Drive is unavailable; using local backup storage",
    )
    struct ICloudUnavailable {}

    @LogEvent("icloud-access-failed", level: .warning)
    struct ICloudAccessFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "iCloud backup access failed; using local storage: \(error.description)"
        }
    }

    @LogEvent("ignored-unrecognized-file", level: .warning)
    struct IgnoredUnrecognizedFile {
        @LogField(exposure: .restricted, kind: .identifier)
        var name: String
        var message: String {
            "Ignored unrecognized automatic-backup file: \(name)"
        }
    }

    @LogEvent("cleanup-failed", level: .warning)
    struct CleanupFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError
        var message: String {
            "Automatic-backup staging cleanup failed: \(error.description)"
        }
    }
}
