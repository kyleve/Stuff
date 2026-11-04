import Synchronization

/// One scope's irrevocable access lifetime. The save and revocation share a lock, so a
/// suspended write either commits before retirement or fails without saving its staged changes.
final class DataAccessPermit: Sendable {
    @TaskLocal static var current: DataAccessPermit?
    private let revoked = Mutex(false)
    let policy: DataCompatibilityPolicy
    let requiredMajor: UInt
    private let onCompatibilityFailure: @Sendable (any Error) -> Void

    init(
        policy: DataCompatibilityPolicy,
        requiredMajor: UInt,
        onCompatibilityFailure: @escaping @Sendable (any Error) -> Void,
    ) {
        self.policy = policy
        self.requiredMajor = requiredMajor
        self.onCompatibilityFailure = onCompatibilityFailure
    }

    enum AccessError: Error, Equatable {
        case revoked
        case differentScope
    }

    func rejectAdmission(_ error: any Error) {
        revoke()
        onCompatibilityFailure(error)
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
        do {
            return try await Self.$current.withValue(self) {
                let result = try await operation()
                // Success here does not authorize later publication. An earlier save stays durable.
                try validate()
                return result
            }
        } catch let error as DataCompatibilityError {
            switch error {
                case .activationNotReady, .upgradeRequiresConfirmation, .concurrentChange: break
                case .updateRequired, .verificationRequired, .accountChanged, .incompleteRecord,
                     .conflictingRecord, .unsupportedStore:
                    rejectAdmission(error)
            }
            throw error
        } catch let error as DataCompatibilityAdmissionError {
            rejectAdmission(error.underlyingError)
            throw error.underlyingError
        }
    }
}
