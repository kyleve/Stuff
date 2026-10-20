import Foundation

/// A consumer-owned reference directory, independent of appearance identifiers.
public struct SnapshotReferenceGroup: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty,
              rawValue.range(of: "^[a-z][a-z0-9-]*$", options: .regularExpression) != nil,
              rawValue != "other"
        else { return nil }
        self.rawValue = rawValue
    }

    public static let themes = SnapshotReferenceGroup(rawValue: "themes")!
}
