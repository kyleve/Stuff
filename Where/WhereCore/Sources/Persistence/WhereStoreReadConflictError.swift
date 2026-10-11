/// An external commit changed the evidence read by a pending store mutation.
/// The transaction was discarded before saving; callers must read fresh evidence.
public enum WhereStoreReadConflictError: Error, Sendable, Equatable {
    case changedDuringTransaction
}
