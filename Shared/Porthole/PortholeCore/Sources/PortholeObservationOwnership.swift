import Foundation

/// Native clients attach an owner to nested invocations; owner identities never enter tool
/// arguments.
public struct PortholeObservationOwnerID: Sendable, Hashable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public enum PortholeObservationOwnership {
    @TaskLocal public static var current: PortholeObservationOwnerID?
}

/// A native transport closes its owned observations even when a reply or explicit stop was lost.
public protocol PortholeObservationOwning: Sendable {
    func stopObservations(ownedBy owner: PortholeObservationOwnerID) async
}
