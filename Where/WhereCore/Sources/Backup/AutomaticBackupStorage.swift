import CryptoKit
import Foundation
import ZIPFoundation

/// Stores encrypted automatic backups in iCloud Drive when it can, falling
/// back to this installation's Documents directory. Only recognized encrypted
/// containers participate in the shared newest-three retention policy.
public actor AutomaticBackupStorage {
    public enum StorageError: Error, LocalizedError {
        case documentsDirectoryUnavailable
        case downloadPending
        case iCloudAndLocalWriteFailed(iCloud: String, local: String)

        public var errorDescription: String? {
            switch self {
                case .documentsDirectoryUnavailable:
                    "The app Documents directory is unavailable."
                case .downloadPending:
                    "An iCloud backup has not finished downloading. Try again later."
                case let .iCloudAndLocalWriteFailed(iCloud, local):
                    "The backup could not be saved to iCloud (\(iCloud)) or this device (\(local))."
            }
        }
    }

    private struct Root {
        let url: URL
        let location: AutomaticBackupFile.StorageLocation
    }

    private let backupService: BackupService
    private let iCloudRoot: @Sendable () throws -> URL?
    private let localRoot: @Sendable () throws -> URL
    private let fileManager: FileManager
    private let retainedFileCount: Int
    private static let logger = WhereLog.backup(AutomaticBackupLog.self)

    public init(
        iCloudContainerIdentifier: String = "iCloud.com.stuff.where",
        retainedFileCount: Int = 3,
    ) {
        backupService = BackupService()
        fileManager = .default
        self.retainedFileCount = retainedFileCount
        iCloudRoot = {
            FileManager.default.url(forUbiquityContainerIdentifier: iCloudContainerIdentifier)?
                .appendingPathComponent("Documents/Where Backups", isDirectory: true)
        }
        localRoot = {
            guard let documents = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask,
            ).first else {
                throw StorageError.documentsDirectoryUnavailable
            }
            return documents.appendingPathComponent("Where Backups", isDirectory: true)
        }
    }

    @_spi(Testing)
    public init(
        iCloudRoot: @escaping @Sendable () throws -> URL?,
        localRoot: @escaping @Sendable () throws -> URL,
        retainedFileCount: Int = 3,
    ) {
        backupService = BackupService()
        fileManager = .default
        self.iCloudRoot = iCloudRoot
        self.localRoot = localRoot
        self.retainedFileCount = retainedFileCount
    }

    @discardableResult
    public func store(_ stagedArchive: URL) throws -> AutomaticBackupFile {
        try Task.checkCancellation()
        var iCloudFailure: Error?
        do {
            if let cloudRoot = try iCloudRoot() {
                return try write(
                    stagedArchive,
                    to: Root(url: cloudRoot, location: .iCloudDrive),
                    coordinated: true,
                )
            } else {
                Self.logger { .iCloudUnavailable }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logger { .iCloudAccessFailed(description: error.localizedDescription) }
            iCloudFailure = error
        }

        do {
            return try write(
                stagedArchive,
                to: Root(url: localRoot(), location: .appDocuments),
                coordinated: false,
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let iCloudFailure {
                throw StorageError.iCloudAndLocalWriteFailed(
                    iCloud: iCloudFailure.localizedDescription,
                    local: error.localizedDescription,
                )
            }
            throw error
        }
    }

    public func catalog() throws -> AutomaticBackupCatalog {
        var files: [AutomaticBackupFile] = []
        var isICloudUnavailable = false

        do {
            if let cloudRoot = try iCloudRoot() {
                files += try enumerate(
                    Root(url: cloudRoot, location: .iCloudDrive),
                    coordinated: true,
                )
            } else {
                isICloudUnavailable = true
                Self.logger { .iCloudUnavailable }
            }
        } catch {
            isICloudUnavailable = true
            Self.logger { .iCloudAccessFailed(description: error.localizedDescription) }
        }

        files += try enumerate(
            Root(url: localRoot(), location: .appDocuments),
            coordinated: false,
        )
        return AutomaticBackupCatalog(
            files: files.sorted {
                if $0.exportedAt == $1.exportedAt { return $0.url.path < $1.url.path }
                return $0.exportedAt > $1.exportedAt
            },
            isICloudUnavailable: isICloudUnavailable,
        )
    }

    private func write(
        _ source: URL,
        to root: Root,
        coordinated: Bool,
    ) throws -> AutomaticBackupFile {
        try Task.checkCancellation()
        let metadata = try describe(source, location: root.location)
        try fileManager.createDirectory(at: root.url, withIntermediateDirectories: true)
        let destination = root.url.appendingPathComponent(source.lastPathComponent)
        let operation = { (coordinatedURL: URL) in
            let temporary = coordinatedURL.deletingLastPathComponent()
                .appendingPathComponent(".\(UUID().uuidString).tmp")
            defer { self.removeStagingItemIfPresent(at: temporary) }
            try self.fileManager.copyItem(at: source, to: temporary)
            try Task.checkCancellation()
            try self.fileManager.moveItem(at: temporary, to: coordinatedURL)
            return coordinatedURL
        }
        let storedURL: URL = if coordinated {
            try CoordinatedBackupFileAccess.write(
                at: destination,
                options: [],
                operation: operation,
            )
        } else {
            try operation(destination)
        }
        // No fallible work after the atomic commit: the caller must learn that
        // this file exists even if later catalog or retention work fails.
        return AutomaticBackupFile(
            url: storedURL,
            exportedAt: metadata.exportedAt,
            byteCount: metadata.byteCount,
            storageLocation: root.location,
            protection: metadata.protection,
        )
    }

    private func enumerate(_ root: Root, coordinated: Bool) throws -> [AutomaticBackupFile] {
        let urls: [URL]
        do {
            let operation = { (url: URL) in
                try self.fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles],
                )
            }
            urls = try coordinated
                ? CoordinatedBackupFileAccess.read(at: root.url, operation: operation)
                : operation(root.url)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
        var files: [AutomaticBackupFile] = []
        for url in urls where url.pathExtension.lowercased() == "wherebackup" {
            try Task.checkCancellation()
            // A matching extension alone does not make this one of our
            // automatic files. Ignore malformed or foreign containers
            // so catalog and retention never delete unrecognized data.
            do {
                let operation = { (coordinatedURL: URL) in
                    try self.describe(coordinatedURL, location: root.location)
                }
                let file = try coordinated
                    ? CoordinatedBackupFileAccess.read(at: url, operation: operation)
                    : operation(url)
                files.append(file)
            } catch is BackupService.EncryptedBackupError {
                Self.logger { .ignoredUnrecognizedFile(name: url.lastPathComponent) }
            } catch is DecodingError {
                Self.logger { .ignoredUnrecognizedFile(name: url.lastPathComponent) }
            } catch is Archive.ArchiveError {
                Self.logger { .ignoredUnrecognizedFile(name: url.lastPathComponent) }
            }
        }
        return files
    }

    private func describe(
        _ url: URL,
        location: AutomaticBackupFile.StorageLocation,
    ) throws -> AutomaticBackupFile {
        let cloudValues = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        if cloudValues.ubiquitousItemDownloadingStatus == .notDownloaded {
            try fileManager.startDownloadingUbiquitousItem(at: url)
            throw StorageError.downloadPending
        }
        // Archive's failable initializer cannot distinguish I/O from format
        // errors. Check readability first so access failures remain observable.
        let handle = try FileHandle(forReadingFrom: url)
        try handle.close()
        let envelope = try backupService.readEncryptedEnvelope(at: url)
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return AutomaticBackupFile(
            url: url,
            exportedAt: envelope.exportedAt,
            byteCount: values?.fileSize.map(Int64.init),
            storageLocation: location,
            protection: .aesGCM256,
        )
    }

    /// Only authenticated, readable archives with available recovery keys may
    /// displace another recoverable archive. Unknown keys and invalid files stay.
    public func reconcileRetention(recoveryKeys: BackupRecoveryKeyProvider) async throws {
        let catalog = try catalog()
        struct VerifiedFile: Sendable {
            let file: AutomaticBackupFile
            let digest: SHA256.Digest
            let exportedAt: Date
        }
        var verified: [VerifiedFile] = []
        for file in catalog.files {
            try Task.checkCancellation()
            let identifier = try CoordinatedBackupFileAccess.read(at: file.url) {
                try self.backupService.readEncryptedEnvelope(at: $0).keyIdentifier
            }
            guard let key = try await recoveryKeys.loadExisting(identifier: identifier) else {
                continue
            }
            do {
                let candidate = try CoordinatedBackupFileAccess.read(at: file.url) { url in
                    _ = try self.backupService.readEncryptedArchive(at: url, recoveryKey: key)
                    return try VerifiedFile(
                        file: file,
                        digest: SHA256.hash(data: Data(contentsOf: url, options: .mappedIfSafe)),
                        exportedAt: self.backupService.readEncryptedEnvelope(at: url).exportedAt,
                    )
                }
                verified.append(candidate)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Self.logger { .ignoredUnrecognizedFile(name: file.url.lastPathComponent) }
            }
        }
        let ordered = verified.sorted {
            if $0.exportedAt == $1.exportedAt { return $0.file.url.path < $1.file.url.path }
            return $0.exportedAt > $1.exportedAt
        }
        for candidate in ordered.dropFirst(retainedFileCount) {
            try Task.checkCancellation()
            try CoordinatedBackupFileAccess
                .write(at: candidate.file.url, options: .forDeleting) { url in
                    // A replaced or modified file must be reconsidered next time,
                    // never deleted using a stale validation result.
                    let digest = try SHA256.hash(data: Data(
                        contentsOf: url,
                        options: .mappedIfSafe,
                    ))
                    guard digest == candidate.digest else { return }
                    try Task.checkCancellation()
                    try self.fileManager.removeItem(at: url)
                }
        }
    }

    private func removeStagingItemIfPresent(at url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            Self.logger { .cleanupFailed(description: error.localizedDescription) }
        }
    }
}
