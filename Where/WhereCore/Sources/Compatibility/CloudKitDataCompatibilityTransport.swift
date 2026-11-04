import CloudKit
import Foundation

/// Owns one account-scoped head in a private custom zone, separate from SwiftData's mirror.
/// Conditional server saves establish major activation; ordinary history never uses this path.
public actor CloudKitDataCompatibilityTransport: SharedDataCompatibilityTransport {
    private let database: any DataCompatibilityControlDatabase
    private var observingAccount: DataCompatibilityAccountID?

    public init(containerIdentifier: String) {
        database =
            CloudKitDataCompatibilityControlDatabase(containerIdentifier: containerIdentifier)
    }

    init(database: any DataCompatibilityControlDatabase) {
        self.database = database
    }

    public func accountID() async throws -> DataCompatibilityAccountID {
        try await database.accountID()
    }

    public func verify(accountID: DataCompatibilityAccountID) async throws
        -> SharedDataCompatibilityVerification
    {
        try await requireAccount(accountID)
        if let head = try await database.head(accountID: accountID) {
            let state = head
            try await prepareUpdates(accountID: accountID)
            try await requireAccount(accountID)
            return .init(accountID: accountID, history: .existing(state))
        }
        // SwiftData writes only in custom zones. Any pre-existing non-control custom zone is
        // conservatively legacy, including an empty one. Listing failure never means newness.
        let hasLegacyZone = try await database.hasLegacyZone()
        try await requireAccount(accountID)
        return .init(
            accountID: accountID,
            history: hasLegacyZone ? .legacyAccount : .newAccount,
        )
    }

    public func initialize(
        accountID: DataCompatibilityAccountID,
        newAccountMajor: UInt,
    ) async throws -> SharedDataCompatibilityState {
        let verification = try await verify(accountID: accountID)
        let major: UInt
        switch verification.history {
            case let .existing(state): return state
            case .legacyAccount: major = 0
            case .newAccount: major = newAccountMajor
        }
        try await prepareUpdates(accountID: accountID)
        // A head created since inspection wins. The conditional save below closes the remaining
        // race. Legacy clients must be retired by rollout before incompatible activation.
        if let established = try await database.head(accountID: accountID) {
            try await requireAccount(accountID)
            return established
        }
        do { return try await save(accountID: accountID, major: major, expectedRevision: nil) }
        catch {
            if (error as? DataCompatibilityError) == .concurrentChange || Self.isConflict(error),
               let established = try await database.head(accountID: accountID)
            {
                try await requireAccount(accountID)
                return established
            }
            // A network failure can follow a successful save. The next attempt verifies shared
            // state again rather than assuming the earlier request rolled back.
            throw error
        }
    }

    public func advance(
        from expected: SharedDataCompatibilityState,
        to requiredMajor: UInt,
    ) async throws -> SharedDataCompatibilityState {
        try await requireAccount(expected.accountID)
        guard requiredMajor >= expected.requiredMajor,
              let current = try await database.head(accountID: expected.accountID),
              current == expected
        else { throw DataCompatibilityError.concurrentChange }
        return try await save(
            accountID: expected.accountID,
            major: requiredMajor,
            expectedRevision: expected.revision,
        )
    }

    public nonisolated func accountChanges() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>
            .makeStream(bufferingPolicy: .bufferingNewest(1))
        let task = Task {
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                guard !Task.isCancelled else { break }
                continuation.yield()
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private func requireAccount(_ expected: DataCompatibilityAccountID) async throws {
        guard try await accountID() == expected else { throw DataCompatibilityError.accountChanged }
    }

    private func prepareUpdates(accountID: DataCompatibilityAccountID) async throws {
        guard observingAccount != accountID else { return }
        try await database.prepareControlZone()
        try await requireAccount(accountID)
        observingAccount = accountID
    }

    private func save(
        accountID: DataCompatibilityAccountID,
        major: UInt,
        expectedRevision: SharedDataCompatibilityState.Revision?,
    ) async throws -> SharedDataCompatibilityState {
        try await requireAccount(accountID)
        let saved = try await database.saveHead(
            accountID: accountID,
            requiredMajor: major,
            expectedRevision: expectedRevision,
        )
        try await requireAccount(accountID)
        return saved
    }

    private static func isConflict(_ error: any Error) -> Bool {
        guard let error = error as? CKError else { return false }
        if error.code == .serverRecordChanged { return true }
        guard error.code == .partialFailure,
              let errors = error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: any Error]
        else { return false }
        return errors.values.contains(where: isConflict)
    }
}
