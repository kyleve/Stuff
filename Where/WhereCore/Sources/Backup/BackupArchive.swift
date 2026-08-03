import Foundation
import RegionKit

/// Versioned, `Codable` manifest describing a whole-database backup of the
/// Where feature. Serialized to `manifest.json` at the root of the backup
/// `.zip`; evidence blob bytes live alongside it under `assets/` and are
/// linked back to their records by `BackupAssetEntry`.
///
/// The arrays represent the persisted collections (`SDLocationSample` /
/// `SDEvidence` / `SDManualDay` / `SDDismissedIssue` / `SDTrackedRegion`) via
/// their value-type representations, plus the split recording profile / nickname /
/// policy rows. The check-in collection remains in the versioned shape for compatibility, but
/// exports leave it empty and imports ignore it: a backup cannot restore a target installation's
/// live proof that policy was applied and its local outbox was cleared.
public struct BackupArchive: Codable, Sendable, Hashable {
    /// Bumped whenever the archive's on-disk shape changes in a way older
    /// readers can't understand, so an importer can refuse a file it doesn't
    /// know how to read instead of silently dropping data (see
    /// `BackupService.readArchive`, which rejects any other version).
    ///
    /// v3 added sample device provenance plus the first recording-device shape.
    /// v4 split that shape into immutable profiles, append-only nickname metadata,
    /// target-owned check-ins, and append-only complete-authority policy events. v5 adds the
    /// logical data epoch in which each immutable profile registered. v6 adds causal parent
    /// metadata and state-preserving Merge barriers. v7 expands that metadata to a sorted parent
    /// set so one semantic command can causally join every observed concurrent head. There's no
    /// in-app decode
    /// fallback for an older archive — it is reshaped out of band by
    /// `Tools/upgrade-backup.rb`, matching the module's no-migration-on-read rule (see
    /// `AGENTS.md`).
    public static let currentFormatVersion = 7

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
    /// Immutable installation profiles.
    public let recordingDeviceProfiles: [RecordingDeviceProfile]
    /// Full append-only nickname history.
    public let recordingDeviceMetadataChanges: [RecordingDeviceMetadataChange]
    /// Compatibility field for target-owned acknowledgements. New exports leave it empty and
    /// imports never apply it as live authority.
    public let recordingDeviceCheckIns: [RecordingDeviceCheckIn]
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
        recordingDeviceProfiles: [RecordingDeviceProfile],
        recordingDeviceMetadataChanges: [RecordingDeviceMetadataChange],
        recordingDeviceCheckIns: [RecordingDeviceCheckIn],
        recordingPolicyChanges: [RecordingPolicyChange],
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
        self.recordingDeviceProfiles = recordingDeviceProfiles
        self.recordingDeviceMetadataChanges = recordingDeviceMetadataChanges
        self.recordingDeviceCheckIns = recordingDeviceCheckIns
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
