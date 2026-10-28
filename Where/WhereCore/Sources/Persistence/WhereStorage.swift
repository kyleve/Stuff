import Foundation
import StorageKit
import SwiftData

/// Owns Where's shared history store in a dedicated StorageKit tree.
/// The app, share extension, and Inspector must use this same path and schema.
enum WhereStorage {
    struct AppGroupUnavailableError: Error {}

    private static let namespace: StorageKey = "Where"
    private static let shared: StorageKey = "shared"
    private static let history: StorageKey = "history"

    private static func baseURL(groupContainerURL: URL) -> URL {
        groupContainerURL.appending(
            path: "Library/Application Support",
            directoryHint: .isDirectory,
        )
    }

    static func storeURL(groupContainerURL: URL) -> URL {
        baseURL(groupContainerURL: groupContainerURL)
            .appending(path: namespace.name, directoryHint: .isDirectory)
            .appending(path: shared.name, directoryHint: .isDirectory)
            .appending(path: history.name, directoryHint: .isDirectory)
            .appending(path: "\(history.name).store", directoryHint: .notDirectory)
    }

    static func makeContainer(
        groupContainerURL: URL,
        cloudKit: CloudKitOption,
    ) async throws -> ModelContainer {
        let storage = try StorageSystem(
            namespace,
            mode: .persistent(base: .custom(baseURL(groupContainerURL: groupContainerURL))),
        )
        let shared = try await storage.container(Self.shared)
        return try await shared.swiftData.modelContainer(
            for: SwiftDataStore.inspectorModelTypes,
            named: history,
            cloudKit: cloudKit,
        )
    }
}
