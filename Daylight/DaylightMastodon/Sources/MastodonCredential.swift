import Foundation

/// Binds a secret to its verified account even if persisting the connection subsequently fails.
public struct MastodonCredential: Codable, Sendable {
    public let connection: MastodonSettings.Connection
    public let token: String
    public init(connection: MastodonSettings.Connection, token: String) {
        self.connection = connection; self.token = token
    }
}
