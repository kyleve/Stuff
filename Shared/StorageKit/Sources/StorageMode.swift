/// How a `StorageSystem` — and the whole container tree below it — persists.
///
/// The mode is set once on the `StorageSystem` and inherited by every container,
/// so test and preview code can flip a single switch and nothing below has to
/// know it is running against ephemeral storage. The vending namespaces
/// (`StorageContainer.keyValue.store()` / `.swiftData.modelContainer(for:)`) do
/// "the right thing" for each mode automatically.
///
/// `.persistent` carries its `base` so the two are inseparable — you can't ask for
/// on-disk storage without saying *where*, and `.inMemory` can't carry a base it
/// would ignore. The base is consumed once, at `StorageSystem` init, to resolve
/// the root directory; containers below the root only ever branch on
/// persistent-vs-in-memory.
public enum StorageMode: Sendable {
    /// Real files under `base`; UserDefaults suites and SwiftData stores persist
    /// across launches.
    case persistent(base: BaseDirectory)

    /// Ephemeral: files live in a temp directory removed by `deleteAll()`,
    /// key-value stores are in-memory, and SwiftData stores are
    /// `isStoredInMemoryOnly`. No app or model code needs to know.
    case inMemory
}
