import Foundation

/// Account-wide data semantics. Increase only before shipping an incompatible data change.
/// Version 1 also describes history written before the compatibility gate existed.
public struct DataModelVersion: RawRepresentable, Codable, Hashable, Comparable, Sendable {
    public static let current = Self(rawValue: 1)
    public static let baseline = Self(rawValue: 1)
    public let rawValue: Int

    public init(rawValue: Int) {
        precondition(rawValue > 0)
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(Int.self)
        guard value > 0 else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "A data compatibility version must be positive.",
            )
        }
        rawValue = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// CloudKit's opaque user-record identity, scoped to the configured container.
public struct DataCompatibilityAccountID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
