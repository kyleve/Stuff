import Foundation

/// Stable identity for one scene or on-device projection demand.
public struct ProjectionOutputID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(rawValue.isEmpty == false, "A projection output must have an identity")
        self.rawValue = rawValue
    }
}
