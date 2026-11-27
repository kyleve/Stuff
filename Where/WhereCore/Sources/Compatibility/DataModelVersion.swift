import Foundation

/// Account-wide data semantics. Increase only before shipping an incompatible data change.
public struct DataModelVersion: RawRepresentable, Codable, Hashable, Comparable, Sendable {
    private struct Change {
        let version: DataModelVersion
        let reason: LocalizedStringResource
    }

    public static let baseline = Self(rawValue: 1)
    private static let changes: [Change] = [
        // Version 1 also describes history written before the compatibility gate existed.
        Change(version: baseline, reason: .compatibilityVersion1Reason),
        Change(version: Self(rawValue: 2), reason: .compatibilityVersion2Reason),
        Change(version: Self(rawValue: 3), reason: .compatibilityVersion3Reason),
        Change(version: Self(rawValue: 4), reason: .compatibilityVersion4Reason),
        Change(version: Self(rawValue: 5), reason: .compatibilityVersion5Reason),
    ]
    public static let current = changes.last!.version
    public let rawValue: Int

    var changeReason: DataModelChangeReason? {
        guard let change = Self.changes.first(where: { $0.version == self }) else { return nil }
        return DataModelChangeReason(resource: change.reason, bundle: .module)
    }

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
