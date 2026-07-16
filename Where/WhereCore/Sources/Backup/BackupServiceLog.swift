import PeriscopeCore

/// Structured events for `BackupService`'s archive read/write. Evidence ids ride
/// on `externalID` so a skipped blob traces back to its evidence row.
enum BackupServiceLog: LogEvent {
    /// Names the service's timed spans.
    enum SpanName: Hashable {
        case writeArchive
        case readArchive
    }

    case wroteBackup(
        sampleCount: Int,
        evidenceCount: Int,
        manualDayCount: Int,
        dismissedIssueCount: Int,
        trackedRegionCount: Int,
    )
    case assetMissing(evidenceID: String)

    static let eventName = "BackupService"

    var level: LogLevel {
        switch self {
            case .wroteBackup: .info
            case .assetMissing: .warning
        }
    }

    var message: String {
        switch self {
            case let .wroteBackup(
            sampleCount,
            evidenceCount,
            manualDayCount,
            dismissedIssueCount,
            trackedRegionCount,
        ):
                "Wrote backup with \(sampleCount) samples, \(evidenceCount) evidence, \(manualDayCount) manual days, \(dismissedIssueCount) dismissals, \(trackedRegionCount) tracked regions"
            case let .assetMissing(evidenceID):
                "Backup asset missing for evidence \(evidenceID); skipping blob"
        }
    }

    var externalID: String? {
        switch self {
            case let .assetMissing(evidenceID): evidenceID
            case .wroteBackup: nil
        }
    }
}
