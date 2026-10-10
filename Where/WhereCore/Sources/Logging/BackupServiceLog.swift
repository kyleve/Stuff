import PeriscopeCore

/// Structured events and spans for `BackupService`.
@LogScope("BackupService")
enum BackupServiceLog {
    enum SpanName: Hashable {
        case stageAssets
        case encodeManifest
        case writeArchive
        case readArchive
        case decodeManifest
        case loadAssets
    }

    @LogEvent("wrote-backup")
    struct WroteBackup {
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
            "Wrote backup with \(sampleCount) samples, \(evidenceCount) evidence, "
                + "\(manualDayCount) manual days, \(dismissedIssueCount) dismissals, "
                + "\(trackedRegionCount) tracked regions"
        }
    }

    @LogEvent("asset-missing", level: .warning)
    struct AssetMissing {
        @LogField(exposure: .restricted, kind: .identifier)
        var evidenceID: String
        var message: String {
            "Backup asset missing for evidence \(evidenceID); skipping blob"
        }

        var externalID: String? {
            WhereStoreID.evidence(evidenceID)
        }
    }
}
