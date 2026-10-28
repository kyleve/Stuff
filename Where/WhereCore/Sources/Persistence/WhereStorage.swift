import Foundation
import StorageKit
import SwiftData

/// Maps StorageKit containers onto Where's existing App Group store layout.
/// The app, share extension, and Inspector must use this same path and schema.
/// This compatibility adapter returns only the model container. It never exposes
/// tree deletion: the existing Application Support directory can also hold logs.
enum WhereStorage {
    struct AppGroupUnavailableError: Error {}

    private enum Directory: String {
        case library = "Library"
        case applicationSupport = "Application Support"
    }

    private static let storeName: StorageKey = "default"

    static func storeURL(groupContainerURL: URL) -> URL {
        groupContainerURL
            .appending(path: Directory.library.rawValue, directoryHint: .isDirectory)
            .appending(path: Directory.applicationSupport.rawValue, directoryHint: .isDirectory)
            .appending(path: "\(storeName.name).store", directoryHint: .notDirectory)
    }

    static func makeContainer(
        groupContainerURL: URL,
        cloudKit: CloudKitOption,
    ) async throws -> ModelContainer {
        // Use the entitlement-resolved directory as the root. Its system-assigned
        // name is unwrapped only at this filesystem boundary.
        let storage = try StorageSystem(
            StorageKey(groupContainerURL.lastPathComponent),
            mode: .persistent(base: .custom(groupContainerURL.deletingLastPathComponent())),
        )
        let library = try await storage.container(StorageKey(Directory.library))
        return try await library.swiftData.modelContainer(
            for: SwiftDataStore.inspectorModelTypes,
            directory: StorageKey(Directory.applicationSupport),
            named: storeName,
            cloudKit: cloudKit,
        )
    }
}
