import Foundation

/// One admitted store lifetime. A replacement access value never revives the previous permit.
public final class DataCompatibilityAccess: Sendable {
    public struct ID: Hashable, Sendable {
        let rawValue: UUID
    }

    public let id: ID
    public let requiredMajor: UInt
    public let store: any WhereStore
    let permit: DataAccessPermit

    init(
        base: any WhereStore,
        requiredMajor: UInt,
        policy: DataCompatibilityPolicy,
        onFailure: @escaping @Sendable (any Error, ID) -> Void,
    ) {
        let accessID = ID(rawValue: UUID())
        id = accessID
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
