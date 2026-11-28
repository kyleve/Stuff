import Foundation

/// Identifies one opening or animation run. Copies retain the same identity.
public struct PresentationID<Owner>: Hashable, Sendable {
    private let value = UUID()

    public init() {}
}
