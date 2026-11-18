import Foundation

extension StorageContainer {
    /// The key-value namespace for this container: a namespaced `UserDefaults`
    /// suite (`.persistent`) or an in-memory store (`.inMemory`). See
    /// ``KeyValueStorage``.
    public nonisolated var keyValue: KeyValueStorage {
        KeyValueStorage(container: self)
    }
}

/// The `keyValue` namespace of a ``StorageContainer`` — a tiny `Sendable` facade
/// vending the node's namespaced key-value store. Vend it with
/// `container.keyValue`.
public struct KeyValueStorage: Sendable {
    let container: StorageContainer

    /// Vend this node's namespaced key-value store: a `UserDefaults` suite in
    /// `.persistent` mode, an in-memory store in `.inMemory` mode. Cached per node
    /// (repeated calls return the same instance) and dropped by `deactivate()` /
    /// `deleteContainer()`.
    ///
    /// - Important: This is deliberately **non-throwing** so the common case reads
    ///   like `store.bool(forKey:)` without a `try`. The price is that calling it
    ///   on a container that is being deleted or is already deleted is a
    ///   **programmer error and traps** — don't wrap every access in
    ///   `try`/`catch`. Reach for the store through a live handle and stop using it
    ///   once you've torn its container down (e.g. release it in an `onDeactivate`
    ///   handler); a vend racing a concurrent delete is the one case where the
    ///   trap can fire, and that's a lifecycle bug to fix at the call site, not to
    ///   defend against on each call. Use `container(_:)` /
    ///   `swiftData.modelContainer(for:)` instead if you need a throwing failure
    ///   mode.
    public func store() async -> any KeyValueStore {
        await container.makeKeyValueStore()
    }
}

extension StorageContainer {
    /// Actor-isolated backing for `keyValue.store()`. Lives here beside its facade
    /// so the key-value concern stays out of the core `StorageContainer` file.
    func makeKeyValueStore() -> any KeyValueStore {
        requireLiveForKeyValueVend()
        if let cached = keyValueStoreCache {
            return cached
        }
        let store: any KeyValueStore
        switch mode {
            case .persistent:
                guard let suite = UserDefaults(suiteName: suiteName) else {
                    preconditionFailure(
                        "StorageKit: invalid UserDefaults suite name \"\(suiteName)\"",
                    )
                }
                store = UserDefaultsKeyValueStore(suite)
            case .inMemory:
                store = InMemoryKeyValueStore()
        }
        keyValueStoreCache = store
        return store
    }
}
