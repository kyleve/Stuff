import PeriscopeCore

/// Structured events for `BackupModel`.
@LogScope("Backup")
enum BackupModelLog {
    @LogEvent("exported", message: "Exported backup archive")
    struct Exported {}

    @LogEvent("export-failed", level: .warning)
    struct ExportFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Backup export failed: \(description)"
        }
    }

    @LogEvent("imported")
    struct Imported {
        @LogField(exposure: .shareable, kind: .count)
        var sampleCount: Int
        @LogField(exposure: .shareable, kind: .count)
        var evidenceCount: Int
        @LogField(exposure: .shareable, kind: .count)
        var manualDayCount: Int
        @LogField(exposure: .shareable, kind: .count)
        var dismissedIssueCount: Int
        @LogField(exposure: .shareable, kind: .count)
        var trackedRegionCount: Int

        var message: String {
            "Imported backup (\(sampleCount) samples, \(evidenceCount) evidence, "
                + "\(manualDayCount) manual days, \(dismissedIssueCount) dismissals, "
                + "\(trackedRegionCount) tracked regions)"
        }
    }

    @LogEvent("import-failed", level: .warning)
    struct ImportFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Backup import failed: \(description)"
        }
    }

    @LogEvent("import-cleanup-failed", level: .warning)
    struct ImportCleanupFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Backup import committed but recording cleanup failed: \(description)"
        }
    }
}
