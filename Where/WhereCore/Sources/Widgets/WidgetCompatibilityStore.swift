import Foundation

/// Atomic App Group sidecar inspected before reading any cached widget data.
public struct WidgetCompatibilityStore: Sendable {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func shared(appGroupIdentifier: String) throws -> Self {
        guard let directory = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else {
            throw WidgetSnapshotStore.AppGroupUnavailableError()
        }
        return Self(directory: directory)
    }

    private var fileURL: URL {
        directory.appending(path: "widget-compatibility.json")
    }

    public func write(_ snapshot: WidgetCompatibilitySnapshot) throws {
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
    }

    public func read() throws -> WidgetCompatibilitySnapshot? {
        do {
            return try JSONDecoder().decode(
                WidgetCompatibilitySnapshot.self,
                from: Data(contentsOf: fileURL),
            )
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }
}
