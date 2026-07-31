import Foundation

/// Resolves and reads Where's App Group glance artifact.
///
/// This boundary is intentionally read-only. The app remains the only writer;
/// widgets and the menu bar helper decode the app's last successful publish.
public struct WhereSurfaceStore: Sendable, WhereSurfaceReading {
    /// Thrown when the process does not have access to Where's App Group.
    public struct AppGroupUnavailableError: Error {
        public init() {}
    }

    public static let appGroupIdentifier = "group.com.stuff.where"
    public static let snapshotFileName = "widget-snapshot.json"

    public static var openWhereURL: URL {
        guard let url = URL(string: "where://open") else {
            preconditionFailure("The static Where URL is invalid")
        }
        return url
    }

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func shared() throws -> WhereSurfaceStore {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier,
        ) else {
            throw AppGroupUnavailableError()
        }
        return WhereSurfaceStore(directory: container)
    }

    public func read() throws -> WhereSurfaceDocument? {
        let fileURL = directory.appending(path: Self.snapshotFileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(WhereSurfaceDocument.self, from: data)
    }
}
