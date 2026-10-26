/// Explicit compatibility fixture for injected services. It owns no account control plane and
/// leaves its caller-owned service lifetime intact when a preview or unit test replaces a scope.
@_spi(Testing)
public struct IsolatedDataCompatibility: DataCompatibilityChecking {
    public init() {}
    public func changes() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }

    public func snapshot() async -> DataCompatibilitySnapshot {
        .init(
            revision: 0,
            state: .compatible(.current),
        )
    }

    public func recheck() async -> DataCompatibilityState {
        .compatible(.current)
    }

    public func recheckLocalHistory() async -> DataCompatibilityState {
        .compatible(.current)
    }

    public func invalidateAccount() async {}
    public func revokeAccess() async {}
    public func retireScope(_: WhereServices) async {}
}
