import PeriscopeCore

/// Structured events for `BackupModel`, the export/import view model. Failures
/// leave the UI in an honest error state, so they log at `.warning`.
enum BackupModelLog: LogEvent {
    case exported
    case exportFailed(description: String)
    case imported(
        sampleCount: Int,
        evidenceCount: Int,
        manualDayCount: Int,
        dismissedIssueCount: Int,
        trackedRegionCount: Int,
    )
    case importFailed(description: String)
    case importCleanupFailed(description: String)

    static let eventName = "Backup"

    var level: LogLevel {
        switch self {
            case .exported, .imported: .info
            case .exportFailed, .importFailed, .importCleanupFailed: .warning
        }
    }

    var message: String {
        switch self {
            case .exported:
                "Exported backup archive"
            case let .exportFailed(description):
                "Backup export failed: \(description)"
            case let .imported(
            sampleCount,
            evidenceCount,
            manualDayCount,
            dismissedIssueCount,
            trackedRegionCount,
        ):
                "Imported backup (\(sampleCount) samples, \(evidenceCount) evidence, \(manualDayCount) manual days, \(dismissedIssueCount) dismissals, \(trackedRegionCount) tracked regions)"
            case let .importFailed(description):
                "Backup import failed: \(description)"
            case let .importCleanupFailed(description):
                "Backup import committed but recording cleanup failed: \(description)"
        }
    }

    var remoteFields: [RemoteLogField] {
        switch self {
            case let .imported(
            sampleCount,
            evidenceCount,
            manualDayCount,
            dismissedIssueCount,
            trackedRegionCount,
        ):
                [
                    RemoteLogField(
                        key: RemoteLogFieldKey("sample_count"),
                        value: .count(sampleCount),
                    ),
                    RemoteLogField(
                        key: RemoteLogFieldKey("evidence_count"),
                        value: .count(evidenceCount),
                    ),
                    RemoteLogField(
                        key: RemoteLogFieldKey("manual_day_count"),
                        value: .count(manualDayCount),
                    ),
                    RemoteLogField(
                        key: RemoteLogFieldKey("dismissed_issue_count"),
                        value: .count(dismissedIssueCount),
                    ),
                    RemoteLogField(
                        key: RemoteLogFieldKey("tracked_region_count"),
                        value: .count(trackedRegionCount),
                    ),
                ]
            case .exported, .exportFailed, .importFailed, .importCleanupFailed:
                []
        }
    }
}
