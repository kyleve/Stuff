import Foundation
import RegionKit

/// Versioned, `Codable` manifest describing a whole-database backup of the
/// Where feature. Serialized to `manifest.json` at the root of the backup
/// `.zip`; evidence blob bytes live alongside it under `assets/` and are
/// linked back to their records by `BackupAssetEntry`.
///
/// The arrays mirror the SwiftData tables exactly (`SDLocationSample` /
/// `SDEvidence` / `SDManualDay` / `SDDismissedIssue` / `SDTrackedRegion`) via
/// their value-type representations, plus `SDRecordingDevice` /
/// `SDRecordingPolicyChange`, so an export captures everything and an import
/// can upsert it back row-for-row.
public struct BackupArchive: Codable, Sendable, Hashable {
    /// Bumped whenever the archive's on-disk shape changes in a way older
    /// readers can't understand, so an importer can refuse a file it doesn't
    /// know how to read instead of silently dropping data (see
    /// `BackupService.readArchive`, which rejects any other version).
    ///
    /// v3 adds sample device provenance plus the synced recording-device and
    /// append-only policy tables, and stores dates as lossless Unix epoch
    /// seconds. There's no in-app decode fallback for an older archive — it is
    /// reshaped out of band by `Tools/upgrade-backup.rb`, matching the module's
    /// no-migration-on-read rule (see `AGENTS.md`).
    public static let currentFormatVersion = 3

    public let formatVersion: Int
    public let exportedAt: Date
    public let samples: [LocationSample]
    public let evidence: [Evidence]
    public let manualDays: [DayPresence]
    /// Data-resolution dismissals (issue id + when dismissed), so a restore
    /// keeps issues the user already dismissed dismissed.
    public let dismissedIssues: [DismissedIssue]
    /// The user's tracked regions at export time (region ids only), so a restore
    /// carries the region selection. Retained alongside ``primaryRegions`` as the
    /// bare-id list `upgrade-backup.rb` and the import summary count read.
    public let trackedRegions: [Region]
    /// The user's primary regions at export time, each with its picked
    /// ``RegionAppearance`` (color / emoji / icon) and pick order, so a restore
    /// brings back the *look*, not just the region set. Import restores from
    /// this; `trackedRegions` is the derived id list.
    public let primaryRegions: [PrimaryRegion]
    /// Every synced device profile, including archived devices.
    public let recordingDevices: [RecordingDevice]
    /// The full append-only policy timeline for every device.
    public let recordingPolicyChanges: [RecordingPolicyChange]
    /// One entry per evidence record that has blob bytes in the archive.
    /// Evidence without bytes simply has no entry here.
    public let assets: [BackupAssetEntry]

    public init(
        formatVersion: Int = BackupArchive.currentFormatVersion,
        exportedAt: Date,
        samples: [LocationSample],
        evidence: [Evidence],
        manualDays: [DayPresence],
        dismissedIssues: [DismissedIssue],
        trackedRegions: [Region],
        primaryRegions: [PrimaryRegion],
        recordingDevices: [RecordingDevice] = [],
        recordingPolicyChanges: [RecordingPolicyChange] = [],
        assets: [BackupAssetEntry],
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.samples = samples
        self.evidence = evidence
        self.manualDays = manualDays
        self.dismissedIssues = dismissedIssues
        self.trackedRegions = trackedRegions
        self.primaryRegions = primaryRegions
        self.recordingDevices = recordingDevices
        self.recordingPolicyChanges = recordingPolicyChanges
        self.assets = assets
    }
}

/// Links one `Evidence` record to the file holding its blob bytes inside the
/// backup archive. A named struct (rather than a bare dictionary entry or
/// tuple) so the mapping stays self-describing in the public Codable surface.
public struct BackupAssetEntry: Codable, Sendable, Hashable {
    public let evidenceId: UUID
    /// Path of the blob file relative to the archive root, e.g.
    /// `assets/<uuid>`.
    public let filename: String

    public init(evidenceId: UUID, filename: String) {
        self.evidenceId = evidenceId
        self.filename = filename
    }
}
