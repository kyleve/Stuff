import Foundation
import PeriscopeCore

/// Each draft is a separate atomic file, so concurrent share processes cannot overwrite a queue.
/// The directory is excluded from system backup; restore cannot replay an already imported share.
public actor FileSharedEvidenceDraftQueue: SharedEvidenceDraftQueuing {
    public struct AppGroupUnavailable: Error {}
    private let directory: URL
    private let fileManager: FileManager
    private static let logger = WhereLog.root(SharedEvidenceInboxLog.self)

    public init(directory: URL) {
        self.directory = directory
        fileManager = .default
    }

    public static func shared(appGroupIdentifier: String) throws -> FileSharedEvidenceDraftQueue {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier,
        ) else { throw AppGroupUnavailable() }
        return FileSharedEvidenceDraftQueue(directory: container
            .appending(path: "PendingSharedEvidence"))
    }

    public func enqueue(_ draft: SharedEvidenceDraft) throws {
        try draft.validate()
        try prepareDirectory()
        let destination = fileURL(draft.id)
        let staging = directory.appending(path: ".staging-\(UUID().uuidString)")
        try JSONEncoder().encode(draft).write(
            to: staging,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication],
        )
        defer {
            do { try fileManager.removeItem(at: staging) }
            catch { Self.logger.stagingCleanupFailed(error: .restricted(.errorDetails, error)) }
        }
        do {
            // A hard link publishes the complete bytes without replacing another process's file.
            // Foundation rejects an existing destination; an identical retry is then harmless.
            try fileManager.linkItem(at: staging, to: destination)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            guard try read(destination) == draft else {
                throw SharedEvidenceDraft.ValidationError.conflictingIdentity
            }
        }
    }

    public func pendingDraftIDs() throws -> [SharedEvidenceDraft.ID] {
        let files: [URL]
        do {
            files = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
            )
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
        return try files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }.map { file in
                guard let rawID = UUID(uuidString: file.deletingPathExtension().lastPathComponent)
                else { throw SharedEvidenceDraft.ValidationError.conflictingIdentity }
                return SharedEvidenceDraft.ID(rawValue: rawID)
            }
    }

    public func draft(for draftID: SharedEvidenceDraft.ID) throws -> SharedEvidenceDraft? {
        do { return try read(fileURL(draftID)) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }

    public func acknowledge(_ draftID: SharedEvidenceDraft.ID) throws {
        do {
            try fileManager.removeItem(at: fileURL(draftID))
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }

    private func prepareDirectory() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private func fileURL(_ draftID: SharedEvidenceDraft.ID) -> URL {
        directory.appending(path: draftID.rawValue.uuidString).appendingPathExtension("json")
    }

    private func read(_ url: URL) throws -> SharedEvidenceDraft {
        let draft = try JSONDecoder().decode(SharedEvidenceDraft.self, from: Data(contentsOf: url))
        try draft.validate()
        guard fileURL(draft.id).lastPathComponent == url.lastPathComponent else {
            throw SharedEvidenceDraft.ValidationError.conflictingIdentity
        }
        return draft
    }
}
