import PeriscopeCore

/// Structured events and spans for `BackupCoordinator`.
@LogScope("BackupCoordinator")
enum BackupCoordinatorLog {
    enum SpanName: Hashable {
        case exportBackup
        case exportReads
        case exportBlobLoad
        case importBackup
        case importWrite
    }

    @LogEvent("remove-previous-export-failed", level: .warning, version: 2)
    struct RemovePreviousExportFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Failed to remove previous backup export directory: \(error.description)"
        }
    }
}
