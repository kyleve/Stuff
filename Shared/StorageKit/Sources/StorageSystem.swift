import Foundation

/// The root of a StorageKit tree: pure configuration plus a vending point. It
/// owns the `mode`, the resolved namespace directory, and whole-tree teardown,
/// and vends the first level of containers (e.g. one per user id). All actual
/// storage operations live on the `StorageContainer`s it vends — this type does
/// no file work of its own beyond creating its namespace directory.
///
/// The split costs one extra directory level on disk (the layout is an invisible
/// implementation detail) in exchange for keeping "what do I configure" separate
/// from "what do I store".
public actor StorageSystem {
    /// How this system and everything below it persists.
    public nonisolated let mode: StorageMode
    /// The resolved namespace directory (a temp directory in `.inMemory` mode).
    public nonisolated let url: URL

    private let root: StorageContainer

    /// Create a storage system named `name`.
    ///
    /// - `.persistent`: rooted at `<base.resolvedURL>/<name>`.
    /// - `.inMemory`: rooted at a unique temporary directory removed by
    ///   `deleteAll()`; `base` is ignored.
    ///
    /// `fileManager` is injectable so tests can resolve a `.custom` base
    /// deterministically.
    public init(
        _ name: StorageKey,
        mode: StorageMode,
        base: BaseDirectory = .applicationSupport(),
        fileManager: FileManager = .default,
    ) throws {
        self.mode = mode
        let rootURL: URL
        switch mode {
            case .persistent:
                let baseURL = try base.resolvedURL(using: fileManager)
                rootURL = baseURL.appending(path: name.name, directoryHint: .isDirectory)
            case .inMemory:
                rootURL = fileManager.temporaryDirectory.appending(
                    path: "StorageKit-\(name.name)-\(UUID().uuidString)",
                    directoryHint: .isDirectory,
                )
        }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        url = rootURL
        root = StorageContainer(
            key: name,
            url: rootURL,
            mode: mode,
            suiteName: Self.rootSuiteName(name: name, url: rootURL),
            parent: nil,
        )
    }

    /// The root `UserDefaults` suite name for the tree. It folds a stable hash of
    /// the resolved root URL into `name`, so two systems with the same `name` but
    /// different base directories (parallel tests, or genuinely distinct on-disk
    /// locations) get independent global suites instead of clobbering one shared
    /// `"<name>"` domain. Child suites append their keys to this. Unused in
    /// `.inMemory` mode, where key-value stores never touch `UserDefaults`.
    private static func rootSuiteName(name: StorageKey, url: URL) -> String {
        "\(name.name).\(stableHash(url.path))"
    }

    /// A deterministic FNV-1a hash, rendered base-36. `Hasher`/`hashValue` is
    /// seeded per process, so it can't be used here — the suite name must stay
    /// stable across launches for persistence to survive.
    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 36)
    }

    /// Vend a top-level container (e.g. one per user id). Cached and idempotent.
    public func container(_ key: StorageKey) async throws -> StorageContainer {
        try await root.container(key)
    }

    /// Reversibly release the whole tree's handles, keeping all data. The next
    /// vend reactivates.
    public func deactivate() async throws {
        try await root.deactivate()
    }

    /// Delete every container and the namespace directory itself (in `.inMemory`
    /// mode, the temp directory). The system is spent afterwards — build a new one
    /// to start over.
    public func deleteAll() async throws {
        try await root.deleteContainer()
    }
}
