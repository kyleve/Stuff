import Foundation

/// A key in the host's approved symbol registry, not a system symbol name.
public struct ViewSymbolID: RawRepresentable, Codable, Hashable, Sendable {
    public var rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
