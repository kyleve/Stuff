import Foundation

/// Versioned, `Codable` manifest describing a whole-database backup of the
/// Where feature. Serialized to `manifest.json` at the root of the backup
/// `.zip`; evidence blob bytes live alongside it under `assets/` and are
/// linked back to their records by `BackupAssetEntry`.
///
/// The three arrays mirror the three SwiftData tables exactly
/// (`SDLocationSample` / `SDEvidence` / `SDManualDay`) via their value-type
/// representations, so an export captures everything and an import can
/// upsert it back row-for-row.
public struct BackupArchive: Codable, Sendable, Hashable {
    /// Bumped whenever the archive's on-disk shape changes in a way older
    /// readers can't understand, so an importer can refuse a file it doesn't
    /// know how to read instead of silently dropping data.
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let exportedAt: Date
    public let samples: [LocationSample]
    public let evidence: [Evidence]
    public let manualDays: [DayPresence]
    /// One entry per evidence record that has blob bytes in the archive.
    /// Evidence without bytes simply has no entry here.
    public let assets: [BackupAssetEntry]

    public init(
        formatVersion: Int = BackupArchive.currentFormatVersion,
        exportedAt: Date,
        samples: [LocationSample],
        evidence: [Evidence],
        manualDays: [DayPresence],
        assets: [BackupAssetEntry],
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.samples = samples
        self.evidence = evidence
        self.manualDays = manualDays
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
