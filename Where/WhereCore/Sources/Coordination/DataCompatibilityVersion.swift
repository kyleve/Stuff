import Foundation

/// The highest shared-data contract understood by a build. Every version includes earlier ones.
/// This value stays a single ordered number; additional metadata belongs on its enclosing record.
public struct DataCompatibilityVersion: RawRepresentable, Hashable, Comparable, Sendable, Codable {
    public static let current = Self(rawValue: 1)
    public static let initial = Self(rawValue: 1)

    public let rawValue: Int

    public init(rawValue: Int) {
        precondition(rawValue > 0, "Data compatibility versions must be positive.")
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// A bare positive integer is the stable backup and metadata wire shape.
    /// Validate untrusted input here so invalid data throws before reaching the initializer's
    /// programmer precondition.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(Int.self)
        guard value > 0 else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid data compatibility version",
            )
        }
        self.init(rawValue: value)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
