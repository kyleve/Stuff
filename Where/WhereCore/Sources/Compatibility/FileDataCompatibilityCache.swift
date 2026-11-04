import Foundation

/// Atomic, backup-excluded account verification cache. Storage failures never become absence.
@MainActor
public final class FileDataCompatibilityCache: DataCompatibilityCacheStoring {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> DataCompatibilityCache? {
        do { return try JSONDecoder().decode(
            DataCompatibilityCache.self,
            from: Data(contentsOf: fileURL),
        ) } catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }

    public func save(_ value: DataCompatibilityCache) throws {
        var directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try JSONEncoder().encode(value).write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication],
        )
    }
}
