import Foundation
import PeriscopeCore
import RegionKit
import ZIPFoundation

/// Serializes a whole-database backup to a `.zip` and reads one back.
///
/// Archive layout:
/// ```
/// manifest.json         // BackupArchive: samples, evidence, manual days, asset index
/// assets/<evidence-id>  // one file per evidence blob
/// ```
///
/// The service is pure file I/O over value types — it never touches
/// SwiftData. `BackupCoordinator` owns reading the store and committing an
/// import transaction; this type only marshals bytes to and from the zip.
public struct BackupService: Sendable {
    /// Header decoded before the strict current archive shape, so an older manifest reports its
    /// format version instead of failing first on a field introduced by a later format.
    private struct FormatEnvelope: Decodable {
        let formatVersion: Int
    }

    /// Decoded contents of a backup archive: the manifest plus the evidence
    /// blob bytes, keyed by evidence id so the importer can pair them with
    /// the matching `Evidence` metadata.
    public struct ReadResult: Sendable {
        public let archive: BackupArchive
        public let blobs: [UUID: Data]

        public init(archive: BackupArchive, blobs: [UUID: Data]) {
            self.archive = archive
            self.blobs = blobs
        }
    }

    /// Failures specific to reading a backup file. Transport / file-system
    /// errors surface as the underlying `Error` instead.
    public enum BackupError: Error, LocalizedError {
        /// The zip opened but contained no `manifest.json` at its root — it
        /// is almost certainly not a Where backup.
        case manifestMissing
        /// The manifest declares a `formatVersion` this build can't read (it
        /// must match `BackupArchive.currentFormatVersion` exactly).
        case unsupportedFormatVersion(Int)
        /// Recording rows decoded structurally but violate persisted invariants (for example a
        /// a negative causal revision or incomplete removal history).
        case invalidRecordingData

        public var errorDescription: String? {
            switch self {
                case .manifestMissing:
                    String(localized: .backupErrorManifestMissing)
                case let .unsupportedFormatVersion(version):
                    String(localized: .backupErrorUnsupportedFormatVersion(version))
                case .invalidRecordingData:
                    String(localized: .backupErrorInvalidRecordingData)
            }
        }
    }

    private static let manifestFilename = "manifest.json"
    private static let assetsDirectory = "assets"
    private static let logger = WhereLog.backup(BackupServiceLog.self)

    public init() {}

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // ISO8601's Foundation encoder drops sub-second precision. Policy
        // changes deliberately use that precision to preserve the order of
        // rapid local actions, so encode the underlying instant losslessly.
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }

            let value = try container.decode(String.self)
            if let date = try? Date(
                value,
                strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true),
            ) {
                return date
            }
            if let date = try? Date(value, strategy: Date.ISO8601FormatStyle()) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a Unix timestamp or ISO8601 date.",
            )
        }
        return decoder
    }

    // MARK: - Export

    /// Build a backup `.zip` from the supplied data and return a URL to the
    /// file in the temporary directory. The caller owns the file and should
    /// delete it (or its parent directory) once it has been shared.
    ///
    /// `blobs` holds the evidence bytes keyed by `Evidence.id`; evidence
    /// without an entry is exported as metadata only.
    public func makeArchiveFile(
        samples: [LocationSample],
        evidence: [Evidence],
        manualDays: [DayPresence],
        dismissedIssues: [DismissedIssue] = [],
        trackedRegions: [Region] = [],
        primaryRegions: [PrimaryRegion] = [],
        recordingDeviceProfiles: [RecordingDeviceProfile],
        recordingDeviceMetadataChanges: [RecordingDeviceMetadataChange],
        recordingDeviceRemovals: [RecordingDeviceRemoval],
        blobs: [UUID: Data],
        exportedAt: Date = Date(),
        archiveName: String? = nil,
    ) throws -> URL {
        try Self.validateRecordingData(
            metadataChanges: recordingDeviceMetadataChanges,
        )
        let fileManager = FileManager.default
        let workRoot = fileManager.temporaryDirectory
            .appendingPathComponent("where-backup-\(UUID().uuidString)", isDirectory: true)
        let staging = workRoot.appendingPathComponent("contents", isDirectory: true)
        let assetsDir = staging.appendingPathComponent(Self.assetsDirectory, isDirectory: true)
        try fileManager.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        var assetEntries: [BackupAssetEntry] = []
        try Self.logger.measure(.stageAssets) {
            for item in evidence {
                guard let blob = blobs[item.id] else { continue }
                // Drain each write's file-I/O scratch (URL/Data bridging) per
                // iteration so a large evidence set doesn't pile up autoreleased
                // temporaries until the whole export finishes.
                try autoreleasepool {
                    let filename = "\(Self.assetsDirectory)/\(item.id.uuidString)"
                    try blob.write(to: staging.appendingPathComponent(filename))
                    assetEntries.append(BackupAssetEntry(evidenceId: item.id, filename: filename))
                }
            }
        }

        let archive = BackupArchive(
            exportedAt: exportedAt,
            samples: samples,
            evidence: evidence,
            manualDays: manualDays,
            dismissedIssues: dismissedIssues,
            trackedRegions: trackedRegions,
            primaryRegions: primaryRegions,
            recordingDeviceProfiles: recordingDeviceProfiles,
            recordingDeviceMetadataChanges: recordingDeviceMetadataChanges,
            recordingDeviceRemovals: recordingDeviceRemovals,
            assets: assetEntries,
        )
        try Self.logger.measure(.encodeManifest) {
            let manifestData = try Self.makeEncoder().encode(archive)
            try manifestData.write(to: staging.appendingPathComponent(Self.manifestFilename))
        }

        let name = archiveName ?? Self.defaultArchiveName(for: exportedAt)
        let zipURL = workRoot.appendingPathComponent(name)
        try Self.logger.measure(.writeArchive) {
            try fileManager.zipItem(
                at: staging,
                to: zipURL,
                shouldKeepParent: false,
                compressionMethod: .deflate,
            )
        }
        Self.logger {
            .wroteBackup(
                sampleCount: samples.count,
                evidenceCount: evidence.count,
                manualDayCount: manualDays.count,
                dismissedIssueCount: dismissedIssues.count,
                trackedRegionCount: trackedRegions.count,
            )
        }
        return zipURL
    }

    /// A human-friendly, email-ready filename like
    /// `Where Backup 2026-06-05 14.30.zip`. The time uses dots (not colons,
    /// which are invalid in filenames) so two exports on the same day don't
    /// collide.
    static func defaultArchiveName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return "Where Backup \(formatter.string(from: date)).zip"
    }

    // MARK: - Import

    /// Unzip and decode a backup file. The archive is extracted into a unique
    /// temporary directory that is removed before returning; the decoded
    /// manifest and blob bytes are held in memory in the result.
    public func readArchive(at url: URL) throws -> ReadResult {
        let fileManager = FileManager.default
        let extractDir = fileManager.temporaryDirectory
            .appendingPathComponent("where-import-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: extractDir) }

        try Self.logger.measure(.readArchive) {
            try fileManager.unzipItem(at: url, to: extractDir)
        }

        let manifestURL = extractDir.appendingPathComponent(Self.manifestFilename)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw BackupError.manifestMissing
        }
        let archive = try Self.logger.measure(.decodeManifest) {
            try Self.decodeManifest(Data(contentsOf: manifestURL))
        }
        try Self.validateRecordingData(archive)

        let blobs = try Self.loadAssets(archive.assets, from: extractDir)
        return ReadResult(archive: archive, blobs: blobs)
    }

    /// Load every blob the manifest explicitly declares. Evidence without an asset entry remains
    /// intentionally metadata-only; an entry whose file is absent or unreadable is a corrupt
    /// archive and must throw before `BackupCoordinator` pauses recording or mutates the store.
    static func loadAssets(
        _ entries: [BackupAssetEntry],
        from extractDirectory: URL,
    ) throws -> [UUID: Data] {
        var blobs: [UUID: Data] = [:]
        try Self.logger.measure(.loadAssets) {
            for entry in entries {
                // Drain the per-read bridging scratch each iteration so walking a
                // large asset set doesn't accumulate transient temporaries (the
                // decoded blobs themselves are retained in `blobs`).
                try autoreleasepool {
                    let assetURL = extractDirectory.appendingPathComponent(entry.filename)
                    do {
                        blobs[entry.evidenceId] = try Data(contentsOf: assetURL)
                    } catch {
                        Self.logger { .assetMissing(evidenceID: entry.evidenceId.uuidString) }
                        throw error
                    }
                }
            }
        }
        return blobs
    }

    static func decodeManifest(_ data: Data) throws -> BackupArchive {
        let decoder = makeDecoder()
        let envelope = try decoder.decode(FormatEnvelope.self, from: data)
        guard envelope.formatVersion == BackupArchive.currentFormatVersion else {
            throw BackupError.unsupportedFormatVersion(envelope.formatVersion)
        }
        return try decoder.decode(BackupArchive.self, from: data)
    }

    /// Validate invariants that synthesized `Decodable` cannot route through the public
    /// initializers. Kept separate so malformed input is rejected before the import transaction,
    /// rather than being committed and silently disappearing from later materialized reads.
    static func validateRecordingData(_ archive: BackupArchive) throws {
        try validateRecordingData(
            metadataChanges: archive.recordingDeviceMetadataChanges,
        )
    }

    private static func validateRecordingData(
        metadataChanges: [RecordingDeviceMetadataChange],
    ) throws {
        guard metadataChanges.allSatisfy({ $0.revision >= 0 }) else {
            throw BackupError.invalidRecordingData
        }
    }
}
