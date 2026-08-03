import Foundation
import PeriscopeCore

/// One retryable raw sample together with the logical generation that authorized it. The epoch
/// token is load-bearing: a sample captured before reset can be discarded, but can never be
/// reclassified and written into the post-reset account state.
public struct LocationOutboxEntry: Codable, Sendable, Hashable {
    public let sample: LocationSample
    public let dataEpochID: WhereDataEpochID

    public init(sample: LocationSample, dataEpochID: WhereDataEpochID) {
        self.sample = sample
        self.dataEpochID = dataEpochID
    }
}

/// A durable backlog of GPS samples that failed to persist, so a transient
/// store outage (SwiftData/CloudKit) that *outlives the process* doesn't
/// silently drop measurements: the backlog is reloaded and re-tried on the next
/// `LocationIngestor.start()`.
///
/// Deliberately separate from `WhereStore`: the store is the thing that's
/// failing when samples land here, so the backlog must not depend on it. The
/// production implementation is a small atomically-written JSON file in the
/// app's own sandbox, explicitly excluded from device backups (the samples are
/// sensitive raw locations — not the App Group the widget reads).
public protocol LocationOutbox: Sendable {
    /// The persisted backlog, or empty when none exists. A read/security/decoding failure throws;
    /// callers must not treat an unreadable raw-location file as an empty successful load.
    func load() async throws -> [LocationOutboxEntry]
    /// Replace the persisted backlog with `entries`; an empty array clears it.
    func save(_ entries: [LocationOutboxEntry]) async
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

    public func save(_: [LocationOutboxEntry]) async {}
    public func clear() async throws {}
}

/// File-backed `LocationOutbox`: the backlog is one atomically-written JSON file
/// (write-to-temp-then-rename), so a crash mid-write can never corrupt a
/// previously good backlog. An `actor` so its disk I/O runs off the
/// `LocationIngestor`'s executor.
public actor FileLocationOutbox: LocationOutbox {
    private static let directoryName = "LocationRetryOutbox"
    private static let fileName = "outbox.json"
    private static let legacyFileName = "location-retry-outbox.json"

    private let fileURL: URL
    /// Retained when composing the production outbox so a failed legacy migration cannot leave
    /// raw locations outside the scope of a later reset.
    private let legacyFileURL: URL?
    private let readData: @Sendable (URL) throws -> Data
    private let excludeFromBackup: @Sendable (URL) throws -> Void

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
            logger { .noApplicationSupport }
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
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return []
        }
        do {
            try excludeFromBackup(fileURL.deletingLastPathComponent())
            try excludeFromBackup(fileURL)
        } catch {
            Self.logger(attachments: [.error(error, name: "backup-exclusion-error")]) {
                .excludeFromBackupFailed(description: error.localizedDescription)
            }
            Self.discardInsecureFile(at: fileURL)
            throw error
        }

        let data: Data
        do {
            data = try readData(fileURL)
        } catch {
            // File protection and transient I/O failures can clear later. Preserve the only
            // durable copy so a subsequent load can retry it.
            Self.logger(attachments: [.error(error, name: "read-error")]) {
                .readBacklogFailed(description: error.localizedDescription)
            }
            throw error
        }

        do {
            return try Self.decodeEntries(from: data)
        } catch {
            // Decoding validly read bytes cannot recover without a format change. Drop them rather
            // than crash-looping on the same corrupt backlog every launch.
            Self.logger(attachments: [.error(error, name: "decode-error")]) {
                .droppedUnreadableBacklog(description: error.localizedDescription)
            }
            Self.discardInsecureFile(at: fileURL)
            throw error
        }
    }

    public func save(_ entries: [LocationOutboxEntry]) async {
        guard !entries.isEmpty else {
            do {
                try await clear()
            } catch {
                Self.logger(attachments: [.error(error, name: "clear-error")]) {
                    .persistBacklogFailed(description: error.localizedDescription)
                }
            }
            return
        }
        var publishedNewFile = false
        do {
            let data = try JSONEncoder().encode(entries)
            let directoryURL = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
            )
            // Secure the empty directory before writing either atomic-write scratch or pending
            // bytes, closing the crash window between a completed write and per-file exclusion.
            try excludeFromBackup(directoryURL)
            let pendingURL = fileURL.appendingPathExtension("pending")
            if FileManager.default.fileExists(atPath: pendingURL.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: pendingURL)
            }
            // Exclude the new inode before it acquires the authoritative path. A crash or
            // exclusion failure can therefore never publish backup-eligible raw locations.
            try data.write(to: pendingURL, options: .atomic)
            try excludeFromBackup(pendingURL)
            if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                _ = try FileManager.default.replaceItemAt(
                    fileURL,
                    withItemAt: pendingURL,
                    backupItemName: nil,
                    options: .usingNewMetadataOnly,
                )
            } else {
                try FileManager.default.moveItem(at: pendingURL, to: fileURL)
            }
            publishedNewFile = true
            try excludeFromBackup(fileURL)
        } catch {
            Self.logger(attachments: [.error(error, name: "persist-error")]) {
                .persistBacklogFailed(description: error.localizedDescription)
            }
            if publishedNewFile {
                Self.discardInsecureFile(at: fileURL)
            }
        }
    }

    public func clear() async throws {
        let pendingURL = fileURL.appendingPathExtension("pending")
        for url in [fileURL, pendingURL] + [legacyFileURL].compactMap(\.self)
            where FileManager.default.fileExists(
                atPath: url.path(percentEncoded: false),
            )
        {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Secure an outbox directory left by an interrupted write even when recording is Off and
    /// the ingestor never loads it. A complete pending file is the newest atomically-written
    /// backlog, so promote it instead of dropping samples merely because the process died before
    /// the final rename. If exclusion cannot be proven for either raw copy, privacy still wins
    /// over that copy's retry durability and it is discarded.
    private static func recoverExistingDirectory(
        containing fileURL: URL,
        fileManager: FileManager,
        excludeFromBackup: @Sendable (URL) throws -> Void,
    ) {
        let directoryURL = fileURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: directoryURL.path(percentEncoded: false))
        else {
            return
        }
        let pendingURL = fileURL.appendingPathExtension("pending")

        do {
            try excludeFromBackup(directoryURL)
        } catch {
            Self.logger(attachments: [.error(error, name: "backup-exclusion-error")]) {
                .excludeFromBackupFailed(description: error.localizedDescription)
            }
        }

        func secureExistingFile(at url: URL) -> Bool {
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
                return false
            }
            do {
                try excludeFromBackup(url)
                return true
            } catch {
                Self.logger(attachments: [.error(error, name: "backup-exclusion-error")]) {
                    .excludeFromBackupFailed(description: error.localizedDescription)
                }
                discardInsecureFile(at: url)
                return false
            }
        }

        _ = secureExistingFile(at: fileURL)
        guard secureExistingFile(at: pendingURL) else {
            return
        }
        let pendingData: Data
        do {
            pendingData = try Data(contentsOf: pendingURL)
        } catch {
            // File protection and transient I/O failures can clear later. Both copies are already
            // excluded, so preserve the pending file for the next construction attempt.
            Self.logger(attachments: [.error(error, name: "pending-read-error")]) {
                .readBacklogFailed(description: error.localizedDescription)
            }
            return
        }
        do {
            _ = try decodeEntries(from: pendingData)
        } catch {
            // Atomic write completion makes a decodable pending file safe to promote. Invalid bytes
            // cannot become a backlog, so retain any older authoritative copy and drop only these.
            Self.logger(attachments: [.error(error, name: "pending-decode-error")]) {
                .droppedUnreadableBacklog(description: error.localizedDescription)
            }
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
            // Both copies remain excluded. Keep them so another launch can retry publication rather
            // than turning a recoverable rename failure into location loss.
            Self.logger(attachments: [.error(error, name: "pending-promotion-error")]) {
                .persistBacklogFailed(description: error.localizedDescription)
            }
            return
        }

        do {
            // Moving preserves the pending inode and replacement metadata rules are subtle. Prove
            // the final authoritative path is still excluded before allowing it to survive.
            try excludeFromBackup(fileURL)
        } catch {
            Self.logger(attachments: [.error(error, name: "backup-exclusion-error")]) {
                .excludeFromBackupFailed(description: error.localizedDescription)
            }
            discardInsecureFile(at: fileURL)
            discardInsecureFile(at: pendingURL)
        }
    }

    /// Move the former single-file outbox into the pre-excluded directory. This runs when the
    /// app composes its outbox, independently of recording policy, so an Off device cannot leave
    /// an older raw-location file backup-eligible indefinitely.
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
            logger(attachments: [.error(error, name: "legacy-migration-error")]) {
                .persistBacklogFailed(description: error.localizedDescription)
            }
            // If migration cannot complete, at least prove the old file is excluded. The helper
            // deletes it when that cannot be guaranteed.
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
            logger(attachments: [.error(error, name: "backup-exclusion-error")]) {
                .excludeFromBackupFailed(description: error.localizedDescription)
            }
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

    /// Decode the epoch-bearing format, with a one-way compatibility path for the pre-epoch
    /// sample array. Legacy entries belong to the implicit initial generation and are therefore
    /// automatically discarded rather than replayed after any destructive rotation.
    private static func decodeEntries(from data: Data) throws -> [LocationOutboxEntry] {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([LocationOutboxEntry].self, from: data)
        } catch let currentError {
            do {
                return try decoder.decode([LocationSample].self, from: data).map {
                    LocationOutboxEntry(sample: $0, dataEpochID: .initial)
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
            logger(attachments: [.error(error, name: "insecure-discard-error")]) {
                .discardInsecureBacklogFailed(description: error.localizedDescription)
            }
        }
    }
}

#if DEBUG
    extension FileLocationOutbox {
        /// Injects a deterministic file reader for testing transient read failures.
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
    }
#endif
