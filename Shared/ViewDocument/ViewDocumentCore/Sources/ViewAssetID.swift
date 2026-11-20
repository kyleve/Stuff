import Foundation

/// A host-supplied image identity, never a URL or filesystem path.
public struct ViewAssetID: RawRepresentable, Codable, Hashable, Sendable {
    public var rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
