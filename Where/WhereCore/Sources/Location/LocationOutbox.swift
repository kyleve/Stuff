import Foundation
import JournalKit
import PeriscopeCore

/// One retryable raw sample together with the logical generation that authorized it. The generation
/// token is load-bearing: a sample captured before reset can be discarded, but can never be
/// reclassified and written into the post-reset account state.
public struct LocationOutboxEntry: Codable, Sendable, Hashable {
    public let sample: LocationSample
    public let dataGenerationID: WhereDataGenerationID

    public init(sample: LocationSample, dataGenerationID: WhereDataGenerationID) {
        self.sample = sample
        self.dataGenerationID = dataGenerationID
    }
}

/// A durable backlog of GPS samples that failed to persist, so a transient
/// store outage (SwiftData/CloudKit) that *outlives the process* doesn't
/// silently drop measurements: the backlog is reloaded and re-tried on the next
/// `LocationIngestor.start()`.
///
/// Deliberately separate from `WhereStore`: the store is the thing that's
/// failing when samples land here, so the backlog must not depend on it. The
/// production implementation journals complete queue snapshots in the app's
/// sandbox, explicitly excluded from device backups (the samples are sensitive
/// raw locations — not the App Group the widget reads).
public protocol LocationOutbox: Sendable {
    /// The persisted backlog, or empty when none exists. A read/security/decoding failure throws;
    /// callers must not treat an unreadable raw-location journal as an empty successful load.
    func load() async throws -> [LocationOutboxEntry]
    /// Replace the persisted backlog with `entries`; an empty array clears it.
    func save(_ entries: [LocationOutboxEntry]) async throws
    /// Remove every persisted retry sample. Reset uses the throwing path so it cannot report a
    /// successful erase while raw locations remain able to repopulate the next installation.
    func clear() async throws
}

/// A no-op outbox: nothing is persisted, so the retry queue is in-memory only
/// (the pre-durability behavior). The safe default for previews/tests and a
/// fallback when no durable location is available.
public struct NoOpLocationOutbox: LocationOutbox {
    public init() {}
    public func load() async throws -> [LocationOutboxEntry] {
        []
    }

    public func save(_: [LocationOutboxEntry]) async throws {}
    public func clear() async throws {}
}

private enum LocationOutboxRecoveryError: Error {
    case noCompleteSnapshot
}

/// Journal-backed `LocationOutbox`. Each entry is a complete bounded retry-queue
/// snapshot, so recovery needs only the newest intact entry and JournalKit may
/// discard older segments without changing queue semantics.
public actor FileLocationOutbox: LocationOutbox {
    private static let directoryName = "LocationRetryOutbox"
    private static let fileName = "outbox.json"
    private static let legacyFileName = "location-retry-outbox.json"
    private static let maximumJournalByteCount = 8 * 1024 * 1024

    private let fileURL: URL
    private let directoryURL: URL
    /// Retained when composing the production outbox so a failed legacy migration cannot leave
    /// raw locations outside the scope of a later reset.
    private let legacyFileURL: URL?
    private let readData: @Sendable (URL) throws -> Data
    private let excludeFromBackup: @Sendable (URL) throws -> Void
    private var journal: Journal?

    private static let logger = WhereLog.location(LocationOutboxLog.self)

    public init(fileURL: URL) {
        self.init(
            fileURL: fileURL,
            legacyFileURL: nil,
            readData: { try Self.readDataFromDisk(at: $0) },
            excludeFromBackup: { try Self.excludeFromBackup($0) },
        )
    }

    init(fileURL: URL, legacyFileURL: URL?) {
        self.init(
            fileURL: fileURL,
            legacyFileURL: legacyFileURL,
            readData: { try Self.readDataFromDisk(at: $0) },
            excludeFromBackup: { try Self.excludeFromBackup($0) },
        )
    }

    private init(
        fileURL: URL,
        legacyFileURL: URL?,
        readData: @escaping @Sendable (URL) throws -> Data,
        excludeFromBackup: @escaping @Sendable (URL) throws -> Void,
    ) {
        self.fileURL = fileURL
        directoryURL = fileURL.deletingLastPathComponent()
        self.legacyFileURL = legacyFileURL
        self.readData = readData
        self.excludeFromBackup = excludeFromBackup
        Self.recoverExistingDirectory(
            containing: fileURL,
            fileManager: .default,
            excludeFromBackup: excludeFromBackup,
        )
    }

    /// An outbox at the app sandbox's Application Support directory, or a
    /// `NoOpLocationOutbox` if that can't be resolved (so ingestion still works,
    /// just without cross-launch durability).
    public static func applicationSupport(
        fileManager: FileManager = .default,
    ) -> any LocationOutbox {
        guard let directory = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true,
        ) else {
            logger.noApplicationSupport()
            return NoOpLocationOutbox()
        }
        let fileURL = directory
            .appending(path: directoryName, directoryHint: .isDirectory)
            .appending(path: fileName)
        let legacyFileURL = directory.appending(path: legacyFileName)
        migrateLegacyFileIfNeeded(
            from: legacyFileURL,
            to: fileURL,
            fileManager: fileManager,
        )
        return FileLocationOutbox(fileURL: fileURL, legacyFileURL: legacyFileURL)
    }

    public func load() async throws -> [LocationOutboxEntry] {
        do {
            try secureDirectoryIfPresent()
            let recovered = try JournalRecovery.recover(directory: directoryURL)
            if recovered.foundTornEntry {
                Self.logger.recoveredTornJournal()
            }
            if let payload = recovered.payloads.last {
                return try Self.decodeEntries(from: payload)
            }
            if recovered.foundTornEntry {
                throw LocationOutboxRecoveryError.noCompleteSnapshot
            }
            return try migrateLegacyJSONIfNeeded()
        } catch {
            Self.logger.readBacklogFailed(
                description: .restricted(.errorDetails, error.localizedDescription),
                attachments: [.error(error, name: "read-error")],
            )
            throw error
        }
    }

    public func save(_ entries: [LocationOutboxEntry]) async throws {
        guard !entries.isEmpty else {
            try await clear()
            return
        }
        do {
            let data = try JSONEncoder().encode(entries)
            try openJournal().append(data, sync: .processDeath)
        } catch {
            Self.logger.persistBacklogFailed(
                description: .restricted(.errorDetails, error.localizedDescription),
                attachments: [.error(error, name: "persist-error")],
            )
            throw error
        }
    }

    public func clear() async throws {
        do {
            if FileManager.default.fileExists(atPath: directoryURL.path(percentEncoded: false)) {
                // The empty checkpoint becomes authoritative before removing old bytes. If the
                // process dies during deletion, recovery still cannot resurrect an older queue.
                try openJournal().append(JSONEncoder().encode([LocationOutboxEntry]()), sync: .full)
                journal?.close()
                journal = nil
                try FileManager.default.removeItem(at: directoryURL)
            }
            if let legacyFileURL,
               FileManager.default.fileExists(atPath: legacyFileURL.path(percentEncoded: false))
            {
                try FileManager.default.removeItem(at: legacyFileURL)
            }
        } catch {
            Self.logger.persistBacklogFailed(
                description: .restricted(.errorDetails, error.localizedDescription),
                attachments: [.error(error, name: "clear-error")],
            )
            throw error
        }
    }

    private func openJournal() throws -> Journal {
        if let journal { return journal }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try excludeFromBackup(directoryURL)
        let opened = try Journal(
            directory: directoryURL,
            configuration: .init(maximumByteCount: Self.maximumJournalByteCount),
        )
        journal = opened
        return opened
    }

    private func secureDirectoryIfPresent() throws {
        guard FileManager.default.fileExists(atPath: directoryURL.path(percentEncoded: false))
        else {
            return
        }
        do {
            try excludeFromBackup(directoryURL)
        } catch {
            Self.logger.excludeFromBackupFailed(
                description: .restricted(.errorDetails, error.localizedDescription),
                attachments: [.error(error, name: "backup-exclusion-error")],
            )
            journal?.close()
            journal = nil
            Self.discardInsecureDirectory(at: directoryURL)
            throw error
        }
    }

    /// Import the previous atomically-written JSON format exactly once. The journal snapshot is
    /// fully durable before the legacy bytes are removed, so interruption can only leave both.
    private func migrateLegacyJSONIfNeeded() throws -> [LocationOutboxEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return []
        }
        let data: Data
        do {
            data = try readData(fileURL)
        } catch {
            // File protection and transient I/O failures can clear later. Preserve the only
            // durable copy so a subsequent load can retry it.
            throw error
        }
        let entries: [LocationOutboxEntry]
        do {
            entries = try Self.decodeEntries(from: data)
        } catch {
            Self.logger.droppedUnreadableBacklog(
                description: .restricted(.errorDetails, error.localizedDescription),
                attachments: [.error(error, name: "decode-error")],
            )
            Self.discardInsecureFile(at: fileURL)
            throw error
        }
        try openJournal().append(JSONEncoder().encode(entries), sync: .full)
        try FileManager.default.removeItem(at: fileURL)
        let pendingURL = fileURL.appendingPathExtension("pending")
        if FileManager.default.fileExists(atPath: pendingURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: pendingURL)
        }
        return entries
    }

    /// Secure an outbox directory left by an interrupted write even when recording is Off and
    /// the ingestor never loads it. A complete pending file is the newest atomically-written
    /// legacy backlog, so promote it instead of dropping samples merely because the process died
    /// before the final rename.
    private static func recoverExistingDirectory(
        containing fileURL: URL,
        fileManager: FileManager,
        excludeFromBackup: @Sendable (URL) throws -> Void,
    ) {
        let directoryURL = fileURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: directoryURL.path(percentEncoded: false)) else {
            return
        }
        let pendingURL = fileURL.appendingPathExtension("pending")

        do {
            try excludeFromBackup(directoryURL)
        } catch {
            logger.excludeFromBackupFailed(
                description: .restricted(.errorDetails, error.localizedDescription),
                attachments: [.error(error, name: "backup-exclusion-error")],
            )
            discardInsecureDirectory(at: directoryURL)
            return
        }

        func secureExistingFile(at url: URL) -> Bool {
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
                return false
            }
            do {
                try excludeFromBackup(url)
                return true
            } catch {
                logger.excludeFromBackupFailed(
                    description: .restricted(.errorDetails, error.localizedDescription),
                    attachments: [.error(error, name: "backup-exclusion-error")],
                )
                discardInsecureFile(at: url)
                return false
            }
        }

        _ = secureExistingFile(at: fileURL)
        guard secureExistingFile(at: pendingURL) else { return }
        let pendingData: Data
        do {
            pendingData = try Data(contentsOf: pendingURL)
        } catch {
            // Both copies are already excluded, so a transient file-protection failure may retry
            // next launch without sacrificing the newer pending snapshot.
            logger.readBacklogFailed(
                description: .restricted(.errorDetails, error.localizedDescription),
                attachments: [.error(error, name: "pending-read-error")],
            )
            return
        }
        do {
            _ = try decodeEntries(from: pendingData)
        } catch {
            logger.droppedUnreadableBacklog(
                description: .restricted(.errorDetails, error.localizedDescription),
                attachments: [.error(error, name: "pending-decode-error")],
            )
            discardInsecureFile(at: pendingURL)
            return
        }

        do {
            if fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                _ = try fileManager.replaceItemAt(
                    fileURL,
                    withItemAt: pendingURL,
                    backupItemName: nil,
                    options: .usingNewMetadataOnly,
                )
            } else {
                try fileManager.moveItem(at: pendingURL, to: fileURL)
            }
        } catch {
            logger.persistBacklogFailed(
                description: .restricted(.errorDetails, error.localizedDescription),
                attachments: [.error(error, name: "pending-promotion-error")],
            )
            return
        }

        do {
            try excludeFromBackup(fileURL)
        } catch {
            logger.excludeFromBackupFailed(
                description: .restricted(.errorDetails, error.localizedDescription),
                attachments: [.error(error, name: "backup-exclusion-error")],
            )
            discardInsecureFile(at: fileURL)
            discardInsecureFile(at: pendingURL)
        }
    }

    /// Move the former root-level file into the pre-excluded directory. This runs when the app
    /// composes its outbox, independently of recording policy.
    private static func migrateLegacyFileIfNeeded(
        from legacyURL: URL,
        to fileURL: URL,
        fileManager: FileManager,
    ) {
        guard fileManager.fileExists(atPath: legacyURL.path(percentEncoded: false)) else { return }
        do {
            try excludeFromBackup(legacyURL)
            let directoryURL = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try excludeFromBackup(directoryURL)
            if fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                try fileManager.removeItem(at: legacyURL)
            } else {
                try fileManager.moveItem(at: legacyURL, to: fileURL)
                try excludeFromBackup(fileURL)
            }
        } catch {
            logger.persistBacklogFailed(
                description: .restricted(.errorDetails, error.localizedDescription),
                attachments: [.error(error, name: "legacy-migration-error")],
            )
            secureExistingFile(at: legacyURL)
        }
    }

    private static func secureExistingFile(at fileURL: URL) {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return
        }
        do {
            try excludeFromBackup(fileURL)
        } catch {
            logger.excludeFromBackupFailed(
                description: .restricted(.errorDetails, error.localizedDescription),
                attachments: [.error(error, name: "backup-exclusion-error")],
            )
            discardInsecureFile(at: fileURL)
        }
    }

    private static func excludeFromBackup(_ fileURL: URL) throws {
        var persistedURL = fileURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try persistedURL.setResourceValues(resourceValues)
    }

    private static func readDataFromDisk(at fileURL: URL) throws -> Data {
        try Data(contentsOf: fileURL)
    }

    /// Decode the generation-bearing format, with a one-way compatibility path for the
    /// pre-generation
    /// sample array. Legacy entries belong to the implicit initial generation and are therefore
    /// automatically discarded rather than replayed after any destructive rotation.
    private static func decodeEntries(from data: Data) throws -> [LocationOutboxEntry] {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([LocationOutboxEntry].self, from: data)
        } catch let currentError {
            do {
                return try decoder.decode([LocationSample].self, from: data).map {
                    LocationOutboxEntry(sample: $0, dataGenerationID: .initial)
                }
            } catch {
                throw currentError
            }
        }
    }

    private static func discardInsecureFile(at fileURL: URL) {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            logger.discardInsecureBacklogFailed(
                description: .restricted(.errorDetails, error.localizedDescription),
                attachments: [.error(error, name: "insecure-discard-error")],
            )
        }
    }

    private static func discardInsecureDirectory(at directoryURL: URL) {
        guard FileManager.default.fileExists(atPath: directoryURL.path(percentEncoded: false))
        else {
            return
        }
        do {
            try FileManager.default.removeItem(at: directoryURL)
        } catch {
            logger.discardInsecureBacklogFailed(
                description: .restricted(.errorDetails, error.localizedDescription),
                attachments: [.error(error, name: "insecure-discard-error")],
            )
        }
    }
}

#if DEBUG
    extension FileLocationOutbox {
        /// Injects a deterministic legacy-file reader for testing transient migration failures.
        @_spi(Testing)
        public init(
            fileURL: URL,
            readData: @escaping @Sendable (URL) throws -> Data,
        ) {
            self.init(
                fileURL: fileURL,
                legacyFileURL: nil,
                readData: readData,
                excludeFromBackup: { try Self.excludeFromBackup($0) },
            )
        }

        /// Injects backup-exclusion behavior to verify privacy fail-closed recovery paths.
        @_spi(Testing)
        public init(
            fileURL: URL,
            readData: @escaping @Sendable (URL) throws -> Data,
            excludeFromBackup: @escaping @Sendable (URL) throws -> Void,
        ) {
            self.init(
                fileURL: fileURL,
                legacyFileURL: nil,
                readData: readData,
                excludeFromBackup: excludeFromBackup,
            )
        }

        /// Closes the current writer so a test can reproduce next-launch recovery over its bytes.
        @_spi(Testing) public func closeJournalForTesting() {
            journal?.close()
            journal = nil
        }
    }
#endif
