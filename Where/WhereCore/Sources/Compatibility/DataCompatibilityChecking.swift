/// Required compatibility behavior at the process bootstrap boundary. Production uses its
/// retained coordinator; injected test worlds supply an explicit conforming implementation.
public protocol DataCompatibilityChecking: Sendable {
    func changes() -> AsyncStream<Void>
    func snapshot() async -> DataCompatibilitySnapshot
    func recheck() async -> DataCompatibilityState
    func recheckLocalHistory() async -> DataCompatibilityState
    func invalidateAccount() async
    func revokeAccess() async
    func retireScope(_ services: WhereServices) async
}
