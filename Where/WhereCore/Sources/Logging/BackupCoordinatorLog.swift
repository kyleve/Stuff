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

    @LogEvent("remove-previous-export-failed", level: .warning)
    struct RemovePreviousExportFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Failed to remove previous backup export directory: \(description)"
        }
    }
}
