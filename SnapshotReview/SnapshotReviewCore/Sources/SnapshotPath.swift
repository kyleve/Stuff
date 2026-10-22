import Foundation

/// A suite-relative image identity. Paths cannot escape the selected suite.
public struct SnapshotPath: Hashable, Codable, Sendable, Comparable {
    public let value: String

    public init(_ value: String) throws {
        guard !value.isEmpty, !value.hasPrefix("/"), !value.contains("\\"),
              value.split(separator: "/", omittingEmptySubsequences: false)
              .allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { throw ReviewError.invalidPath(value) }
        self.value = value
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.value < rhs.value
    }

    /// Validation is required on decode as well as at public construction.
    public init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    /// The wire identity is a single relative path, independent of Swift names.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
