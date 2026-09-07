import CryptoKit
import Foundation
import ZIPFoundation

/// Public metadata at the root of an encrypted `.wherebackup` container.
/// The canonical fields are authenticated as AES-GCM additional data.
public struct EncryptedBackupEnvelope: Codable, Hashable, Sendable {
    public static let currentVersion = 1
    public static let aesGCM256 = "aes-gcm-256"

    public let version: Int
    public let protection: String
    public let keyIdentifier: String
    public let exportedAt: Date

    public init(
        version: Int = EncryptedBackupEnvelope.currentVersion,
        protection: String = EncryptedBackupEnvelope.aesGCM256,
        keyIdentifier: String,
        exportedAt: Date,
    ) {
        self.version = version
        self.protection = protection
        self.keyIdentifier = keyIdentifier
        self.exportedAt = exportedAt
    }

    var authenticatedData: Data {
        Data("\(version)\n\(protection)\n\(keyIdentifier)\n\(exportedAt.timeIntervalSince1970)"
            .utf8)
    }
}

extension BackupService {
    public enum EncryptedBackupError: Error, LocalizedError, Equatable {
        case envelopeMissing
        case encryptedArchiveMissing
        case unsupportedEnvelopeVersion(Int)
        case unsupportedProtection(String)
        case recoveryKeyMismatch
        case authenticationFailed

        public var errorDescription: String? {
            switch self {
                case .envelopeMissing: "This encrypted backup has no envelope."
                case .encryptedArchiveMissing: "This encrypted backup has no archive payload."
                case let .unsupportedEnvelopeVersion(version):
                    "This backup uses unsupported envelope version \(version)."
                case let .unsupportedProtection(protection):
                    "This backup uses unsupported protection \(protection)."
                case .recoveryKeyMismatch: "This recovery key does not match the backup."
                case .authenticationFailed: "The backup could not be authenticated or decrypted."
            }
        }
    }

    /// Encrypts an existing plaintext Where ZIP into a versioned outer ZIP.
    public func makeEncryptedArchiveFile(
        from archiveURL: URL,
        recoveryKey: BackupRecoveryKey,
        exportedAt: Date,
    ) throws -> URL {
        try Task.checkCancellation()
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent(
                "where-encrypted-backup-\(UUID().uuidString)",
                isDirectory: true,
            )
        let staging = root.appendingPathComponent("contents", isDirectory: true)
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            let envelope = EncryptedBackupEnvelope(
                keyIdentifier: recoveryKey.identifier,
                exportedAt: exportedAt,
            )
            let envelopeData = try Self.makeEncoder().encode(envelope)
            try envelopeData.write(
                to: staging.appendingPathComponent("envelope.json"),
                options: .atomic,
            )

            try Task.checkCancellation()
            let plaintext = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
            let sealed = try AES.GCM.seal(
                plaintext,
                using: recoveryKey.symmetricKey,
                authenticating: envelope.authenticatedData,
            )
            try Task.checkCancellation()
            guard let combined = sealed.combined else {
                throw EncryptedBackupError.authenticationFailed
            }
            try combined.write(
                to: staging.appendingPathComponent("archive.aesgcm"),
                options: .atomic,
            )

            try Task.checkCancellation()
            let destination = root
                .appendingPathComponent(Self.automaticArchiveName(for: exportedAt))
            try fileManager.zipItem(
                at: staging,
                to: destination,
                shouldKeepParent: false,
                compressionMethod: .none,
                progress: Self.cancellationProgress,
            )
            try Task.checkCancellation()
            return destination
        } catch {
            Self.removeEncryptedStagingDirectory(root)
            throw error
        }
    }

    /// Reads and decrypts a `.wherebackup` before decoding its unchanged inner
    /// `BackupArchive`. No store mutation occurs in this layer.
    public func readEncryptedArchive(
        at url: URL,
        recoveryKey: BackupRecoveryKey,
    ) throws -> ReadResult {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent(
                "where-encrypted-import-\(UUID().uuidString)",
                isDirectory: true,
            )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { Self.removeEncryptedStagingDirectory(root) }

        try Task.checkCancellation()
        try fileManager.unzipItem(at: url, to: root, progress: Self.cancellationProgress)
        let envelopeURL = root.appendingPathComponent("envelope.json")
        guard fileManager.fileExists(atPath: envelopeURL.path) else {
            throw EncryptedBackupError.envelopeMissing
        }
        let envelope = try Self.makeDecoder().decode(
            EncryptedBackupEnvelope.self,
            from: Data(contentsOf: envelopeURL),
        )
        try validate(envelope)
        guard envelope.keyIdentifier == recoveryKey.identifier else {
            throw EncryptedBackupError.recoveryKeyMismatch
        }

        let payloadURL = root.appendingPathComponent("archive.aesgcm")
        guard fileManager.fileExists(atPath: payloadURL.path) else {
            throw EncryptedBackupError.encryptedArchiveMissing
        }
        let combined = try Data(contentsOf: payloadURL, options: .mappedIfSafe)
        let sealed = try AES.GCM.SealedBox(combined: combined)
        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(
                sealed,
                using: recoveryKey.symmetricKey,
                authenticating: envelope.authenticatedData,
            )
        } catch {
            throw EncryptedBackupError.authenticationFailed
        }
        try Task.checkCancellation()
        let innerURL = root.appendingPathComponent("archive.zip")
        try plaintext.write(to: innerURL, options: .atomic)
        return try readArchive(at: innerURL)
    }

    public func readEncryptedEnvelope(at url: URL) throws -> EncryptedBackupEnvelope {
        guard let archive = Archive(url: url, accessMode: .read),
              let entry = archive["envelope.json"]
        else {
            throw EncryptedBackupError.envelopeMissing
        }
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        let envelope = try Self.makeDecoder().decode(EncryptedBackupEnvelope.self, from: data)
        try validate(envelope)
        return envelope
    }

    private func validate(_ envelope: EncryptedBackupEnvelope) throws {
        guard envelope.version == EncryptedBackupEnvelope.currentVersion else {
            throw EncryptedBackupError.unsupportedEnvelopeVersion(envelope.version)
        }
        guard envelope.protection == EncryptedBackupEnvelope.aesGCM256 else {
            throw EncryptedBackupError.unsupportedProtection(envelope.protection)
        }
    }

    private static func automaticArchiveName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Where Automatic Backup \(formatter.string(from: date)) \(UUID().uuidString).wherebackup"
    }

    private static func removeEncryptedStagingDirectory(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            WhereLog.backup(AutomaticBackupLog.self) {
                .cleanupFailed(description: error.localizedDescription)
            }
        }
    }
}
