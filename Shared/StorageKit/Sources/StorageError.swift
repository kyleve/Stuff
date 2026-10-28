/// Errors thrown by StorageKit operations.
public enum StorageError: Error, Sendable, Equatable {
    /// A container method was used after the container (or one of its ancestors)
    /// was destroyed via `deleteContainer()` / `deleteAll()`. The node is gone;
    /// vend a fresh one from a live `StorageSystem`.
    case containerDeleted(StorageKey)

    /// `swiftData.modelContainer(for:named:)` was called again under the same `named` store
    /// (the associated key) but with a different set of model types than the
    /// already-open store was built with. A store has exactly one schema — vend
    /// distinct schemas under distinct names rather than silently reusing the
    /// first one.
    case modelStoreSchemaMismatch(StorageKey)
}
