/// Platform boundary for the private control record. The transport's verification and retry
/// protocol is exercised unchanged with an isolated, conditional-write database in tests.
protocol DataCompatibilityControlDatabase: Sendable {
    func accountID() async throws -> DataCompatibilityAccountID
    func head(accountID: DataCompatibilityAccountID) async throws -> SharedDataCompatibilityState?
    func hasLegacyZone() async throws -> Bool
    func prepareControlZone() async throws
    func saveHead(
        accountID: DataCompatibilityAccountID,
        requiredMajor: UInt,
        expectedRevision: SharedDataCompatibilityState.Revision?,
    ) async throws -> SharedDataCompatibilityState
}
