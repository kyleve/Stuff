import PeriscopeCore

/// Structured events for `BackupModel`.
@LogScope("Backup")
enum BackupModelLog {
    @LogEvent("exported", message: "Exported backup archive")
    struct Exported {}

    @LogEvent("export-failed", level: .warning)
    struct ExportFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Backup export failed: \(description)"
        }
    }

    @LogEvent("imported")
    struct Imported {
        @LogField("sample_count", exposure: .shareable, kind: .count)
        var sampleCount: Int
        @LogField("evidence_count", exposure: .shareable, kind: .count)
        var evidenceCount: Int
        @LogField("manual_day_count", exposure: .shareable, kind: .count)
        var manualDayCount: Int
        @LogField("dismissed_issue_count", exposure: .shareable, kind: .count)
        var dismissedIssueCount: Int
        @LogField("tracked_region_count", exposure: .shareable, kind: .count)
        var trackedRegionCount: Int

        var message: String {
            "Imported backup (\(sampleCount) samples, \(evidenceCount) evidence, "
                + "\(manualDayCount) manual days, \(dismissedIssueCount) dismissals, "
                + "\(trackedRegionCount) tracked regions)"
        }
    }

    @LogEvent("import-failed", level: .warning)
    struct ImportFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Backup import failed: \(description)"
        }
    }

    @LogEvent("import-cleanup-failed", level: .warning)
    struct ImportCleanupFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String
        var message: String {
            "Backup import committed but recording cleanup failed: \(description)"
        }
    }
}
