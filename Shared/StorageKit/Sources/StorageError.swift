/// Errors thrown by StorageKit operations.
public enum StorageError: Error, Sendable, Equatable {
    /// A container method was used after the container (or one of its ancestors)
    /// was destroyed via `deleteContainer()` / `deleteAll()`. The node is gone;
    /// vend a fresh one from a live `StorageSystem`.
    case containerDeleted(StorageKey)
}
