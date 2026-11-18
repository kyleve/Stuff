import Foundation
import SwiftData

extension StorageContainer {
    /// The SwiftData namespace for this container: isolated `ModelContainer`s whose
    /// stores live in dedicated child directories. See ``SwiftDataStorage``.
    public nonisolated var swiftData: SwiftDataStorage {
        SwiftDataStorage(container: self)
    }
}

/// The `swiftData` namespace of a ``StorageContainer`` — a tiny `Sendable` facade
/// vending isolated SwiftData `ModelContainer`s. Vend it with `container.swiftData`.
public struct SwiftDataStorage: Sendable {
    let container: StorageContainer

    /// Vend a SwiftData `ModelContainer` whose store lives in a dedicated child
    /// container, so the `.store` file and its `-wal` / `-shm` sidecars and any
    /// external-storage blobs are isolated in one directory (deleting that child —
    /// or this container — deletes exactly that store's files). Cached per `named`
    /// key. In `.inMemory` mode the store is `isStoredInMemoryOnly` and CloudKit
    /// is forced off.
    ///
    /// A store name identifies exactly one schema: calling this again under the
    /// same `named` key with a different set of `types` throws
    /// `StorageError.modelStoreSchemaMismatch` rather than handing back the first
    /// container with a mismatched schema. Use distinct names for distinct stores.
    ///
    /// - Important: In `.persistent` mode the store occupies a child container
    ///   named `named` (default `"store"`), in the **same** key namespace as
    ///   `container(_:)`. Don't also vend a plain child under that key — e.g.
    ///   `container("store")` and the default model store would share one
    ///   directory and stomp each other. Pass a distinct `named:` (or avoid that
    ///   key for your own children) to keep them apart.
    public func modelContainer(
        for types: [any PersistentModel.Type],
        named name: StorageKey = "store",
        cloudKit: CloudKitOption = .none,
    ) async throws -> ModelContainer {
        try await container.makeModelContainer(for: types, named: name, cloudKit: cloudKit)
    }
}

extension StorageContainer {
    /// Actor-isolated backing for `swiftData.modelContainer(for:)`. Lives here
    /// beside its facade so the SwiftData concern stays out of the core
    /// `StorageContainer` file.
    func makeModelContainer(
        for types: [any PersistentModel.Type],
        named name: StorageKey,
        cloudKit: CloudKitOption,
    ) throws -> ModelContainer {
        try activate()
        let typeIDs = Set(types.map { ObjectIdentifier($0) })
        if let cached = modelContainerCache[name] {
            guard cached.typeIDs == typeIDs else {
                throw StorageError.modelStoreSchemaMismatch(name)
            }
            return cached.container
        }
        let schema = Schema(types)
        let configuration: ModelConfiguration
        switch mode {
            case .inMemory:
                // No backing files, so don't vend a store child / touch disk.
                configuration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none,
                )
            case .persistent:
                let storeContainer = try container(name)
                let storeURL = storeContainer.url.appending(
                    path: "\(name.name).store",
                    directoryHint: .notDirectory,
                )
                configuration = ModelConfiguration(
                    schema: schema,
                    url: storeURL,
                    cloudKitDatabase: cloudKit.cloudKitDatabase,
                )
        }
        let modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        modelContainerCache[name] = CachedModelStore(container: modelContainer, typeIDs: typeIDs)
        return modelContainer
    }
}
