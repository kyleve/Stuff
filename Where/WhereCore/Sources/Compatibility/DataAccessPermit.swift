import Synchronization

/// One scope's irrevocable access lifetime. The save and revocation share a lock, so a
/// suspended write either commits before retirement or fails without saving its staged changes.
final class DataAccessPermit: Sendable {
    @TaskLocal static var current: DataAccessPermit?
    private let revoked = Mutex(false)

    enum AccessError: Error, Equatable {
        case revoked
        case differentScope
    }

    func revoke() {
        revoked.withLock { $0 = true }
    }

    func validate() throws {
        try revoked.withLock {
            guard !$0 else { throw AccessError.revoked }
        }
    }

    /// Execute only the synchronous physical commit here. The closure must not reenter this
    /// permit. Holding the lock closes the check-then-save race with another executor's revoke.
    func commitWhileValid(_ commit: () throws -> Void) throws {
        try revoked.withLock {
            guard !$0 else { throw AccessError.revoked }
            try Task.checkCancellation()
            try commit()
        }
    }

    func withAccess<T: Sendable>(
        _ operation: @Sendable () async throws -> T,
    ) async throws -> T {
        try validate()
        if let current = Self.current, current !== self {
            throw AccessError.differentScope
        }
        try Task.checkCancellation()
        return try await Self.$current.withValue(self) {
            let result = try await operation()
            // Reject a result that reaches this check after retirement. Success does not
            // authorize later publication, and an earlier physical commit remains durable.
            try validate()
            return result
        }
    }
}
