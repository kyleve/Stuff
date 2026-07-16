import Foundation
import RegionKit

/// Versioned, `Codable` manifest describing a whole-database backup of the
/// Where feature. Serialized to `manifest.json` at the root of the backup
/// `.zip`; evidence blob bytes live alongside it under `assets/` and are
/// linked back to their records by `BackupAssetEntry`.
///
/// The arrays mirror the SwiftData tables exactly (`SDLocationSample` /
/// `SDEvidence` / `SDManualDay` / `SDDismissedIssue` / `SDTrackedRegion`) via
/// their value-type representations, so an export captures everything and an
/// import can upsert it back row-for-row.
public struct BackupArchive: Codable, Sendable, Hashable {
    /// Bumped whenever the archive's on-disk shape changes in a way older
    /// readers can't understand, so an importer can refuse a file it doesn't
    /// know how to read instead of silently dropping data. `dismissedIssues`
    /// and `trackedRegions` were added without a bump because they are additive:
    /// older readers ignore the unknown key, and newer readers tolerate its
    /// absence (see `init(from:)`).
    ///
    /// v2 keys `manualDays` by a timezone-independent `CalendarDay` (`day`)
    /// rather than an absolute `date` instant. This reader still imports v1
    /// archives — `DayPresence` decodes the legacy `date` and recovers its
    /// calendar day — but a pre-v2 build refuses a v2 file with a clear
    /// "newer version" message instead of failing to find `date`.
    public static let currentFormatVersion = 2

    public let formatVersion: Int
    public let exportedAt: Date
    public let samples: [LocationSample]
    public let evidence: [Evidence]
    public let manualDays: [DayPresence]
    /// Data-resolution dismissals (issue key + when dismissed), so a restore
    /// keeps issues the user already dismissed dismissed. Absent in manifests
    /// written before this field existed; those decode to `[]`.
    public let dismissedIssues: [DismissedIssue]
    /// The user's tracked regions at export time (region ids only), so a restore
    /// carries the region selection like any other data. Absent in manifests
    /// written before this field existed; those decode to `[]`. Retained
    /// alongside ``primaryRegions`` for cross-version compatibility — an older
    /// reader that predates `primaryRegions` still recovers the region set from
    /// here (without the picked looks).
    public let trackedRegions: [Region]
    /// The user's primary regions at export time, each with its picked
    /// ``RegionAppearance`` (color / emoji / icon) and pick order, so a restore
    /// brings back the *look*, not just the region set. Additive: absent in
    /// manifests written before it existed (those decode to `[]`, and the
    /// importer falls back to ``trackedRegions``).
    public let primaryRegions: [PrimaryRegion]
    /// One entry per evidence record that has blob bytes in the archive.
    /// Evidence without bytes simply has no entry here.
    public let assets: [BackupAssetEntry]

    public init(
        formatVersion: Int = BackupArchive.currentFormatVersion,
        exportedAt: Date,
        samples: [LocationSample],
        evidence: [Evidence],
        manualDays: [DayPresence],
        dismissedIssues: [DismissedIssue] = [],
        trackedRegions: [Region] = [],
        primaryRegions: [PrimaryRegion] = [],
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
        self.assets = assets
    }

    /// The primary regions to restore: ``primaryRegions`` when present, else a
    /// fallback built from ``trackedRegions`` (older archives) with no picked
    /// appearance and their listed order.
    public var resolvedPrimaryRegions: [PrimaryRegion] {
        if !primaryRegions.isEmpty { return primaryRegions }
        return trackedRegions.enumerated().map { index, region in
            PrimaryRegion(region: region, appearance: nil, order: index)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case exportedAt
        case samples
        case evidence
        case manualDays
        case dismissedIssues
        case trackedRegions
        case primaryRegions
        case assets
    }

    /// Custom decode (encode stays synthesized) so manifests written before
    /// `dismissedIssues` / `trackedRegions` / `primaryRegions` existed still
    /// import: the missing keys decode to `[]` rather than throwing.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        samples = try container.decode([LocationSample].self, forKey: .samples)
        evidence = try container.decode([Evidence].self, forKey: .evidence)
        manualDays = try container.decode([DayPresence].self, forKey: .manualDays)
        dismissedIssues = try container
            .decodeIfPresent([DismissedIssue].self, forKey: .dismissedIssues) ?? []
        trackedRegions = try container
            .decodeIfPresent([Region].self, forKey: .trackedRegions) ?? []
        primaryRegions = try container
            .decodeIfPresent([PrimaryRegion].self, forKey: .primaryRegions) ?? []
        assets = try container.decode([BackupAssetEntry].self, forKey: .assets)
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
