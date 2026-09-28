import Foundation

public struct MastodonSettings: Codable, Equatable, Sendable {
    public enum Visibility: String, CaseIterable, Codable,
        Sendable { case `public`, unlisted, `private` }
    public struct Connection: Codable, Equatable, Sendable {
        public let server: URL
        public let accountID: String
        public let username: String
    }

    public var version = 1
    public var connection: Connection?
    public var enabled = false
    public var visibility: Visibility = .public
    public var caption = "{event} over San Francisco Bay — {date}."
    public static let initial = Self()
}
