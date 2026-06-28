import Foundation

/// Versioned, `Codable` manifest describing a whole-database backup of the
/// Where feature. Serialized to `manifest.json` at the root of the backup
/// `.zip`; evidence blob bytes live alongside it under `assets/` and are
/// linked back to their records by `BackupAssetEntry`.
///
/// The four arrays mirror the four SwiftData tables exactly
/// (`SDLocationSample` / `SDEvidence` / `SDManualDay` / `SDDismissedIssue`) via
/// their value-type representations, so an export captures everything and an
/// import can upsert it back row-for-row.
public struct BackupArchive: Codable, Sendable, Hashable {
    /// Bumped whenever the archive's on-disk shape changes in a way older
    /// readers can't understand, so an importer can refuse a file it doesn't
    /// know how to read instead of silently dropping data. `dismissedIssues`
    /// was added without a bump because it is additive: older readers ignore
    /// the unknown key, and newer readers tolerate its absence (see
    /// `init(from:)`).
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let exportedAt: Date
    public let samples: [LocationSample]
    public let evidence: [Evidence]
    public let manualDays: [DayPresence]
    /// Data-resolution dismissals (issue key + when dismissed), so a restore
    /// keeps issues the user already dismissed dismissed. Absent in manifests
    /// written before this field existed; those decode to `[]`.
    public let dismissedIssues: [DismissedIssue]
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
        assets: [BackupAssetEntry],
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.samples = samples
        self.evidence = evidence
        self.manualDays = manualDays
        self.dismissedIssues = dismissedIssues
        self.assets = assets
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case exportedAt
        case samples
        case evidence
        case manualDays
        case dismissedIssues
        case assets
    }

    /// Custom decode (encode stays synthesized) so manifests written before
    /// `dismissedIssues` existed still import: the missing key decodes to `[]`
    /// rather than throwing.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        samples = try container.decode([LocationSample].self, forKey: .samples)
        evidence = try container.decode([Evidence].self, forKey: .evidence)
        manualDays = try container.decode([DayPresence].self, forKey: .manualDays)
        dismissedIssues = try container
            .decodeIfPresent([DismissedIssue].self, forKey: .dismissedIssues) ?? []
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
