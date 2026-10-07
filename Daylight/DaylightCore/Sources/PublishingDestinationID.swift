import Foundation

public struct PublishingDestinationID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
