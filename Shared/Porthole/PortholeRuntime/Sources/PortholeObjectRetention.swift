import Foundation
import PortholeCore

public struct PortholeObjectPoolID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct PortholeObjectChildKey: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Scope roots survive automatic eviction. Result pools retain only their most recently used
/// handles.
public enum PortholeObjectRetention: Sendable, Equatable {
    case scope
    case bounded(pool: PortholeObjectPoolID, maximumCount: Int)

    public static let results: Self = .bounded(
        pool: .init(rawValue: "porthole.results"),
        maximumCount: 128,
    )
}

/// Registry identity prevents a nested call into another registry from leaking operation leases.
struct PortholeObjectOperation {
    let registryID: UUID
    let operationID: UUID
    @TaskLocal static var current: Self?
}
