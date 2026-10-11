import Synchronization

/// A scope's irrevocable access lifetime. Persistence rechecks it immediately before commit.
final class DataAccessPermit: Sendable {
    @TaskLocal static var current: DataAccessPermit?
    private let revoked = Mutex(false)

    func revoke() {
        revoked.withLock { $0 = true }
    }

    func validate() throws {
        if revoked.withLock({ $0 }) { throw DataCompatibilityError.accessRevoked }
    }

    func withAccess<T: Sendable>(
        _ operation: @Sendable () async throws -> T,
    ) async throws -> T {
        try validate()
        return try await Self.$current.withValue(self) {
            let result = try await operation()
            try validate()
            return result
        }
    }
}
