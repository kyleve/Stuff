/// One process-local grant. Returning to the same account does not revive an old grant.
public struct DataCompatibilityAdmission: Equatable, Sendable {
    public let domain: DataCompatibilityDomain
    let epoch: UInt64
}
