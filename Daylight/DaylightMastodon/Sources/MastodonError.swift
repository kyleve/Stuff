import Foundation

public enum MastodonError: LocalizedError, Sendable {
    case invalidServer, missingCredentials, invalidResponse, credentialStore(Int32)
    public var errorDescription: String? {
        switch self {
            case .invalidServer: "Enter an HTTPS Mastodon server URL without a path or login information."
            case .missingCredentials: "Connect your Mastodon account before enabling publishing."
            case .invalidResponse: "The Mastodon server returned an unexpected response."
            case let .credentialStore(status): "Keychain could not store or read the access token (\(status))."
        }
    }
}
