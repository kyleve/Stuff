/// How a `StorageSystem` — and the whole container tree below it — persists.
///
/// The mode is set once on the `StorageSystem` and inherited by every container,
/// so test and preview code can flip a single switch and nothing below has to
/// know it is running against ephemeral storage. The vending methods
/// (`StorageContainer.keyValueStore()` / `modelContainer(for:)`) do "the right
/// thing" for each mode automatically.
public enum StorageMode: Sendable {
    /// Real files under a base directory; UserDefaults suites and SwiftData
    /// stores persist across launches.
    case persistent

    /// Ephemeral: files live in a temp directory removed by `deleteAll()`,
    /// key-value stores are in-memory, and SwiftData stores are
    /// `isStoredInMemoryOnly`. No app or model code needs to know.
    case inMemory
}
