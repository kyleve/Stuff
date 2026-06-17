import Foundation
import os
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
        /// The manifest declares a `formatVersion` newer than this build can
        /// read (the file was produced by a later app version).
        case unsupportedFormatVersion(Int)

        public var errorDescription: String? {
            switch self {
                case .manifestMissing:
                    "This file isn't a Where backup (no manifest was found)."
                case let .unsupportedFormatVersion(version):
                    "This backup was created by a newer version of Where (format \(version)) and can't be imported."
            }
        }
    }

    private static let manifestFilename = "manifest.json"
    private static let assetsDirectory = "assets"
    private static let logger = Logger(subsystem: "com.stuff.where", category: "BackupService")

    public init() {}

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
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
        blobs: [UUID: Data],
        exportedAt: Date = Date(),
        archiveName: String? = nil,
    ) throws -> URL {
        let fileManager = FileManager.default
        let workRoot = fileManager.temporaryDirectory
            .appendingPathComponent("where-backup-\(UUID().uuidString)", isDirectory: true)
        let staging = workRoot.appendingPathComponent("contents", isDirectory: true)
        let assetsDir = staging.appendingPathComponent(Self.assetsDirectory, isDirectory: true)
        try fileManager.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        var assetEntries: [BackupAssetEntry] = []
        for item in evidence {
            guard let blob = blobs[item.id] else { continue }
            let filename = "\(Self.assetsDirectory)/\(item.id.uuidString)"
            try blob.write(to: staging.appendingPathComponent(filename))
            assetEntries.append(BackupAssetEntry(evidenceId: item.id, filename: filename))
        }

        let archive = BackupArchive(
            exportedAt: exportedAt,
            samples: samples,
            evidence: evidence,
            manualDays: manualDays,
            assets: assetEntries,
        )
        let manifestData = try Self.makeEncoder().encode(archive)
        try manifestData.write(to: staging.appendingPathComponent(Self.manifestFilename))

        let name = archiveName ?? Self.defaultArchiveName(for: exportedAt)
        let zipURL = workRoot.appendingPathComponent(name)
        try fileManager.zipItem(
            at: staging,
            to: zipURL,
            shouldKeepParent: false,
            compressionMethod: .deflate,
        )
        Self.logger.info(
            "Wrote backup with \(samples.count) samples, \(evidence.count) evidence, \(manualDays.count) manual days",
        )
        return zipURL
    }

    /// A human-friendly, email-ready filename like `Where Backup 2026-06-05.zip`.
    static func defaultArchiveName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
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

        try fileManager.unzipItem(at: url, to: extractDir)

        let manifestURL = extractDir.appendingPathComponent(Self.manifestFilename)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw BackupError.manifestMissing
        }
        let manifestData = try Data(contentsOf: manifestURL)
        let archive = try Self.makeDecoder().decode(BackupArchive.self, from: manifestData)
        guard archive.formatVersion <= BackupArchive.currentFormatVersion else {
            throw BackupError.unsupportedFormatVersion(archive.formatVersion)
        }

        var blobs: [UUID: Data] = [:]
        for entry in archive.assets {
            let assetURL = extractDir.appendingPathComponent(entry.filename)
            guard let data = try? Data(contentsOf: assetURL) else {
                Self.logger.fault(
                    "Backup asset missing for evidence \(entry.evidenceId, privacy: .public); skipping blob",
                )
                continue
            }
            blobs[entry.evidenceId] = data
        }
        return ReadResult(archive: archive, blobs: blobs)
    }
}
