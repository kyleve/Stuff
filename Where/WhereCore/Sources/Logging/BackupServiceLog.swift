import PeriscopeCore

/// Structured events for `BackupService`'s archive read/write. Evidence ids ride
/// on `externalID` so a skipped blob traces back to its evidence row.
enum BackupServiceLog: LogEvent {
    /// Names the service's timed spans — the file-I/O legs inside
    /// `BackupCoordinator`'s export/import spans, in the order they run.
    enum SpanName: Hashable {
        /// Writing every evidence blob into the staging directory.
        case stageAssets
        /// Encoding `manifest.json` and writing it. Whole-library JSON, so it's
        /// the leg that scales with sample count rather than attachment size.
        case encodeManifest
        /// Zipping the staging directory into the archive file.
        case writeArchive
        /// Unzipping a backup file into a scratch directory.
        case readArchive
        /// Decoding `manifest.json` back into a `BackupArchive`.
        case decodeManifest
        /// Reading the unzipped evidence blobs back into memory.
        case loadAssets
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
            case let .assetMissing(evidenceID): WhereStoreID.evidence(evidenceID)
            case .wroteBackup: nil
        }
    }
}
