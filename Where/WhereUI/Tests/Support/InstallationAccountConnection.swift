@testable import WhereCore

/// One installation's authenticated connection. Switching this connection does not sign out
/// another phone or rewrite either account's shared database.
actor InstallationAccountConnection: DataCompatibilityControlDatabase {
    private var account: InstallationSharedAccount

    init(account: InstallationSharedAccount) {
        self.account = account
    }

    func switchAccount(to account: InstallationSharedAccount) {
        self.account = account
    }

    func accountID() async -> DataCompatibilityAccountID {
        await account.accountID()
    }

    func head(accountID: DataCompatibilityAccountID) async throws -> SharedDataCompatibilityState? {
        try await account.head(accountID: accountID)
    }

    func hasLegacyZone() async throws -> Bool {
        try await account.hasLegacyZone()
    }

    func prepareControlZone() async throws {
        try await account.prepareControlZone()
    }

    func saveHead(
        accountID: DataCompatibilityAccountID,
        requiredMajor: UInt,
        expectedRevision: SharedDataCompatibilityState.Revision?,
    ) async throws -> SharedDataCompatibilityState {
        try await account.saveHead(
            accountID: accountID,
            requiredMajor: requiredMajor,
            expectedRevision: expectedRevision,
        )
    }
}
