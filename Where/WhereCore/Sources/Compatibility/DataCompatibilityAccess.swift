import Foundation

/// One admitted store lifetime. A replacement access value never revives the previous permit.
public final class DataCompatibilityAccess: Sendable {
    /// A caller must acquire a new scope after revocation; an old permit cannot be revived.
    public enum AccessError: Error, Equatable {
        case revoked
        case differentScope
    }

    /// Verified dataset identity captured when this access was admitted. This is routing
    /// metadata, not a grant; consumers still validate the current access before publication.
    /// The composition root supplies its configured container when binding shared sidecars.
    public enum Identity: Hashable, Sendable {
        case local(storeID: DataCompatibilityDataset.StoreID)
        case cloudKit(
            storeID: DataCompatibilityDataset.StoreID,
            accountID: DataCompatibilityAccountID,
        )
    }

    public struct ID: Hashable, Sendable {
        let rawValue: UUID
    }

    public let id: ID
    public let identity: Identity
    public let requiredMajor: UInt
    public let store: any WhereStore
    let permit: DataAccessPermit

    init(
        base: any WhereStore,
        identity: Identity,
        requiredMajor: UInt,
        policy: DataCompatibilityPolicy,
        onFailure: @escaping @Sendable (any Error, ID) -> Void,
    ) {
        let accessID = ID(rawValue: UUID())
        id = accessID
        self.identity = identity
        self.requiredMajor = requiredMajor
        let permit = DataAccessPermit(policy: policy, requiredMajor: requiredMajor) { onFailure(
            $0,
            accessID,
        ) }
        self.permit = permit
        store = CompatibilityScopedStore(base: base, permit: permit)
    }

    public func revoke() {
        permit.revoke()
    }

    public var isRevoked: Bool {
        permit.isRevoked
    }

    public func validate() throws {
        try permit.validate()
    }

    public func withAccess<T: Sendable>(
        _ operation: @Sendable () async throws -> T,
    ) async throws -> T {
        try await permit.withAccess(operation)
    }

    /// Only synchronous, nonreentrant publication can share the permit's atomic boundary.
    /// Asynchronous system schedulers need an ordered withdrawal after their pending call returns.
    public func publishWhileValid(_ publication: () throws -> Void) throws {
        try permit.commitWhileValid(publication)
    }
}
