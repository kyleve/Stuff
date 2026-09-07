import Foundation
import os

/// Stores encrypted automatic backups in iCloud Drive when it can, falling
/// back to this installation's Documents directory. Only recognized encrypted
/// containers participate in the shared newest-three retention policy.
public actor AutomaticBackupStorage {
    public enum StorageError: Error, LocalizedError {
        case documentsDirectoryUnavailable
        case iCloudAndLocalWriteFailed(iCloud: String, local: String)

        public var errorDescription: String? {
            switch self {
                case .documentsDirectoryUnavailable:
                    "The app Documents directory is unavailable."
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
        if let cloudRoot = try iCloudRoot() {
            do {
                let stored = try write(
                    stagedArchive,
                    to: Root(url: cloudRoot, location: .iCloudDrive),
                    coordinated: true,
                )
                try pruneReachableBackups()
                return stored
            } catch {
                Self.logger { .iCloudAccessFailed(description: error.localizedDescription) }
                iCloudFailure = error
            }
        } else {
            Self.logger { .iCloudUnavailable }
        }

        do {
            let stored = try write(
                stagedArchive,
                to: Root(url: localRoot(), location: .appDocuments),
                coordinated: false,
            )
            try pruneReachableBackups()
            return stored
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
            files: files.sorted { $0.exportedAt > $1.exportedAt },
            isICloudUnavailable: isICloudUnavailable,
        )
    }

    private func write(
        _ source: URL,
        to root: Root,
        coordinated: Bool,
    ) throws -> AutomaticBackupFile {
        try Task.checkCancellation()
        try fileManager.createDirectory(at: root.url, withIntermediateDirectories: true)
        let destination = root.url.appendingPathComponent(source.lastPathComponent)
        let temporary = root.url.appendingPathComponent(".\(UUID().uuidString).tmp")
        defer { removeStagingItemIfPresent(at: temporary) }

        let operation = {
            try self.fileManager.copyItem(at: source, to: temporary)
            try Task.checkCancellation()
            try self.fileManager.moveItem(at: temporary, to: destination)
        }
        if coordinated {
            try coordinateWriting(at: destination, operation: operation)
        } else {
            try operation()
        }
        return try describe(destination, location: root.location)
    }

    private func enumerate(_ root: Root, coordinated: Bool) throws -> [AutomaticBackupFile] {
        guard fileManager.fileExists(atPath: root.url.path) else { return [] }
        let result = OSAllocatedUnfairLock<Result<[AutomaticBackupFile], Error>?>(
            uncheckedState: nil,
        )
        let operation = {
            let value = Result {
                let urls = try self.fileManager.contentsOfDirectory(
                    at: root.url,
                    includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles],
                )
                var files: [AutomaticBackupFile] = []
                for url in urls where url.pathExtension.lowercased() == "wherebackup" {
                    // A matching extension alone does not make this one of our
                    // automatic files. Ignore malformed or foreign containers
                    // so catalog and retention never delete unrecognized data.
                    do {
                        let file = try self.describe(url, location: root.location)
                        files.append(file)
                    } catch {
                        Self.logger { .ignoredUnrecognizedFile(name: url.lastPathComponent) }
                    }
                }
                return files
            }
            result.withLock { $0 = value }
        }
        if coordinated {
            try coordinateReading(at: root.url, operation: operation)
        } else {
            operation()
        }
        guard let value = result.withLock({ $0 }) else {
            preconditionFailure("File coordination did not execute its read accessor.")
        }
        return try value.get()
    }

    private func describe(
        _ url: URL,
        location: AutomaticBackupFile.StorageLocation,
    ) throws -> AutomaticBackupFile {
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

    private func pruneReachableBackups() throws {
        let catalog = try catalog()
        for oldFile in catalog.files.dropFirst(retainedFileCount) {
            try Task.checkCancellation()
            switch oldFile.storageLocation {
                case .iCloudDrive:
                    try coordinateDeleting(at: oldFile.url)
                case .appDocuments:
                    try fileManager.removeItem(at: oldFile.url)
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

    private func coordinateWriting(at url: URL, operation: () throws -> Void) throws {
        var coordinationError: NSError?
        let operationResult = OSAllocatedUnfairLock<Result<Void, Error>?>(uncheckedState: nil)
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url,
            options: .forReplacing,
            error: &coordinationError,
        ) { _ in
            let result = Result { try operation() }
            operationResult.withLock { $0 = result }
        }
        if let coordinationError { throw coordinationError }
        guard let result = operationResult.withLock({ $0 }) else {
            preconditionFailure("File coordination did not execute its write accessor.")
        }
        try result.get()
    }

    private func coordinateReading(at url: URL, operation: () throws -> Void) throws {
        var coordinationError: NSError?
        let operationResult = OSAllocatedUnfairLock<Result<Void, Error>?>(uncheckedState: nil)
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError,
        ) { _ in
            let result = Result { try operation() }
            operationResult.withLock { $0 = result }
        }
        if let coordinationError { throw coordinationError }
        guard let result = operationResult.withLock({ $0 }) else {
            preconditionFailure("File coordination did not execute its read accessor.")
        }
        try result.get()
    }

    private func coordinateDeleting(at url: URL) throws {
        var coordinationError: NSError?
        let operationResult = OSAllocatedUnfairLock<Result<Void, Error>?>(uncheckedState: nil)
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url,
            options: .forDeleting,
            error: &coordinationError,
        ) { coordinatedURL in
            let result = Result { try self.fileManager.removeItem(at: coordinatedURL) }
            operationResult.withLock { $0 = result }
        }
        if let coordinationError { throw coordinationError }
        guard let result = operationResult.withLock({ $0 }) else {
            preconditionFailure("File coordination did not execute its delete accessor.")
        }
        try result.get()
    }
}
