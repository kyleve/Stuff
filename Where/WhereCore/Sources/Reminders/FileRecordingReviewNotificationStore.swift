import Foundation

/// Local, backup-excluded notification context. A system notification carries only the opaque
/// ID; the bounded review scopes stay in this protected sidecar across process launches.
public actor FileRecordingReviewNotificationStore {
    public enum StorageError: Error, Equatable {
        case identityMismatch
        case conflictingContext
    }

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Persist before scheduling the corresponding notification. Existing IDs are immutable:
    /// updating the work creates a new context, so an already delivered alert keeps its scope.
    public func save(_ notification: RecordingReviewNotification) throws {
        try notification.validate()
        if let previous = try load(notification.id) {
            guard previous == notification else { throw StorageError.conflictingContext }
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excludedDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excludedDirectory.setResourceValues(values)
        try JSONEncoder().encode(notification).write(
            to: fileURL(notification.id),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication],
        )
    }

    /// Missing context is distinct from malformed, inaccessible, or mismatched context.
    public func load(_ notificationID: RecordingReviewNotification
        .ID) throws -> RecordingReviewNotification?
    {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL(notificationID))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
        let notification = try JSONDecoder().decode(RecordingReviewNotification.self, from: data)
        try notification.validate()
        guard notification.id == notificationID else { throw StorageError.identityMismatch }
        return notification
    }

    public func remove(_ notificationID: RecordingReviewNotification.ID) throws {
        try removeIfPresent(fileURL(notificationID))
    }

    /// The owner withdraws system requests before clearing account/reset context.
    public func removeAll() throws {
        try removeIfPresent(directory)
    }

    private func fileURL(_ notificationID: RecordingReviewNotification.ID) -> URL {
        directory.appendingPathComponent(notificationID.rawValue.uuidString)
            .appendingPathExtension("json")
    }

    private func removeIfPresent(_ url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }
}
