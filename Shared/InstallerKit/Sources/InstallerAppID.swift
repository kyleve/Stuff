import Foundation

/// Stable app identity, encoded as one path-safe string in the shared catalog.
public struct InstallerAppID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard InstallerPattern.appID.matches(rawValue)
        else { return nil }
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let appID = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid installer app ID",
            )
        }
        self = appID
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
