import Foundation
import StuffCore

public struct GitHubAppConfiguration: Hashable, Sendable {
    public let clientID: String
    public let appSlug: String

    public init(clientID: String, appSlug: String) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.appSlug = appSlug.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var installationURL: URL? {
        guard !appSlug.isEmpty else { return nil }
        return URL(string: "https://github.com/apps/\(appSlug)/installations/new")
    }
}

public struct GitHubAccessToken: Hashable, Sendable {
    let rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "A GitHub token must not be empty")
        self.rawValue = rawValue
    }
}

public struct GitHubDeviceAuthorization: Hashable, Sendable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURL: URL
    public let expiresAt: Date
    public let pollingInterval: Duration

    public init(
        deviceCode: String,
        userCode: String,
        verificationURL: URL,
        expiresAt: Date,
        pollingInterval: Duration,
    ) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.expiresAt = expiresAt
        self.pollingInterval = pollingInterval
    }
}

public struct GitHubTokenPair: Hashable, Codable, Sendable {
    public let accessToken: String
    public let accessTokenExpiresAt: Date?
    public let refreshToken: String?
    public let refreshTokenExpiresAt: Date?

    public init(
        accessToken: String,
        accessTokenExpiresAt: Date?,
        refreshToken: String?,
        refreshTokenExpiresAt: Date?,
    ) {
        precondition(!accessToken.isEmpty, "A GitHub access token must not be empty")
        self.accessToken = accessToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.refreshToken = refreshToken
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
    }
}

public protocol PatchlightSleeping: Sendable {
    func sleep(for duration: Duration) async throws
}

public struct SystemPatchlightSleeper: PatchlightSleeping {
    public init() {}

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

/// Owns secretless device authorization and atomically persists each rotated
/// access/refresh pair as one Keychain value.
public actor GitHubCredentialManager {
    public static let credentialKey = CredentialKey("github-token-pair")
    public static let identityKey = CredentialKey("github-account-identity")

    private let configuration: GitHubAppConfiguration
    private let credentials: any CredentialStore
    private let transport: any PatchlightHTTPTransport
    private let sleeper: any PatchlightSleeping
    private let now: @Sendable () -> Date
    private let debugPersonalAccessToken: GitHubAccessToken?
    private var cachedPair: GitHubTokenPair?

    public init(
        configuration: GitHubAppConfiguration,
        credentials: any CredentialStore,
        transport: any PatchlightHTTPTransport,
    ) {
        self.configuration = configuration
        self.credentials = credentials
        self.transport = transport
        sleeper = SystemPatchlightSleeper()
        now = Date.init
        debugPersonalAccessToken = nil
    }

    #if DEBUG
        @_spi(Testing)
        public init(
            configuration: GitHubAppConfiguration,
            credentials: any CredentialStore,
            transport: any PatchlightHTTPTransport,
            sleeper: any PatchlightSleeping,
            now: @escaping @Sendable () -> Date,
            debugPersonalAccessToken: GitHubAccessToken? = nil,
        ) {
            self.configuration = configuration
            self.credentials = credentials
            self.transport = transport
            self.sleeper = sleeper
            self.now = now
            self.debugPersonalAccessToken = debugPersonalAccessToken
        }
    #endif

    public func hasStoredCredentials() throws -> Bool {
        if debugPersonalAccessToken != nil { return true }
        return try credentials.data(for: Self.credentialKey) != nil
    }

    public func storedIdentity() throws -> GitHubViewer? {
        guard let data = try credentials.data(for: Self.identityKey) else { return nil }
        do {
            return try JSONDecoder().decode(GitHubViewer.self, from: data)
        } catch {
            throw GitHubAuthenticationError.corruptCredentials
        }
    }

    public func storeIdentity(_ viewer: GitHubViewer) throws {
        try credentials.set(JSONEncoder().encode(viewer), for: Self.identityKey)
    }

    public func beginDeviceAuthorization() async throws -> GitHubDeviceAuthorization {
        try requireClientID()
        let response = try await transport.send(PatchlightHTTPRequest(
            method: .post,
            url: GitHubEndpoint.deviceCode,
            headers: GitHubEndpoint.oauthHeaders,
            body: FormEncoding.encode(["client_id": configuration.clientID]),
        ))
        guard response.statusCode == 200 else {
            throw GitHubAuthenticationError.httpStatus(response.statusCode)
        }
        let wire = try decode(DeviceAuthorizationWire.self, from: response.body)
        guard let verificationURL = URL(string: wire.verificationURI),
              verificationURL == GitHubEndpoint.deviceVerification
        else {
            throw GitHubAuthenticationError.invalidResponse
        }
        return GitHubDeviceAuthorization(
            deviceCode: wire.deviceCode,
            userCode: wire.userCode,
            verificationURL: verificationURL,
            expiresAt: now().addingTimeInterval(TimeInterval(wire.expiresIn)),
            pollingInterval: .seconds(wire.interval),
        )
    }

    public func completeDeviceAuthorization(
        _ authorization: GitHubDeviceAuthorization,
    ) async throws -> GitHubAccessToken {
        try requireClientID()
        var interval = authorization.pollingInterval

        while now() < authorization.expiresAt {
            try Task.checkCancellation()
            let response = try await tokenRequest([
                "client_id": configuration.clientID,
                "device_code": authorization.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])

            if let accessToken = response.accessToken {
                let pair = try tokenPair(from: response)
                try persist(pair)
                return GitHubAccessToken(rawValue: accessToken)
            }

            switch response.error {
                case "authorization_pending":
                    try await sleeper.sleep(for: interval)
                case "slow_down":
                    interval = response.interval.map(Duration.seconds) ?? interval + .seconds(5)
                    try await sleeper.sleep(for: interval)
                case "expired_token", "token_expired":
                    throw GitHubAuthenticationError.expired
                case "access_denied":
                    throw GitHubAuthenticationError.accessDenied
                case "device_flow_disabled":
                    throw GitHubAuthenticationError.deviceFlowDisabled
                case "incorrect_client_credentials":
                    throw GitHubAuthenticationError.incorrectClientID
                case "incorrect_device_code", "bad_verification_code":
                    throw GitHubAuthenticationError.invalidDeviceCode
                case .none:
                    throw GitHubAuthenticationError.invalidResponse
                case let .some(code):
                    throw GitHubAuthenticationError.provider(code)
            }
        }
        throw GitHubAuthenticationError.expired
    }

    public func accessToken() async throws -> GitHubAccessToken {
        if let debugPersonalAccessToken { return debugPersonalAccessToken }
        let pair = try loadPair()
        if let expiry = pair.accessTokenExpiresAt,
           expiry <= now().addingTimeInterval(60)
        {
            return try await refresh(pair)
        }
        return GitHubAccessToken(rawValue: pair.accessToken)
    }

    public func removeCredentials() throws {
        cachedPair = nil
        try credentials.remove(Self.credentialKey)
        try credentials.remove(Self.identityKey)
    }

    private func refresh(_ pair: GitHubTokenPair) async throws -> GitHubAccessToken {
        try requireClientID()
        guard let refreshToken = pair.refreshToken,
              pair.refreshTokenExpiresAt.map({ $0 > now() }) ?? true
        else {
            throw GitHubAuthenticationError.reauthorizationRequired
        }
        let response = try await tokenRequest([
            "client_id": configuration.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])
        if response.error == "bad_refresh_token" {
            throw GitHubAuthenticationError.reauthorizationRequired
        }
        guard let accessToken = response.accessToken else {
            throw GitHubAuthenticationError.provider(response.error ?? "invalid_response")
        }
        let newPair = try tokenPair(from: response)
        // One Keychain replacement commits the newly single-use refresh token
        // together with its access token; no half-rotated state is representable.
        try persist(newPair)
        return GitHubAccessToken(rawValue: accessToken)
    }

    private func tokenRequest(_ form: [String: String]) async throws -> TokenWire {
        let response = try await transport.send(PatchlightHTTPRequest(
            method: .post,
            url: GitHubEndpoint.oauthToken,
            headers: GitHubEndpoint.oauthHeaders,
            body: FormEncoding.encode(form),
        ))
        guard response.statusCode == 200 else {
            throw GitHubAuthenticationError.httpStatus(response.statusCode)
        }
        return try decode(TokenWire.self, from: response.body)
    }

    private func tokenPair(from wire: TokenWire) throws -> GitHubTokenPair {
        guard let accessToken = wire.accessToken, !accessToken.isEmpty else {
            throw GitHubAuthenticationError.invalidResponse
        }
        let timestamp = now()
        return GitHubTokenPair(
            accessToken: accessToken,
            accessTokenExpiresAt: wire.expiresIn.map {
                timestamp.addingTimeInterval(TimeInterval($0))
            },
            refreshToken: wire.refreshToken,
            refreshTokenExpiresAt: wire.refreshTokenExpiresIn.map {
                timestamp.addingTimeInterval(TimeInterval($0))
            },
        )
    }

    private func loadPair() throws -> GitHubTokenPair {
        if let cachedPair { return cachedPair }
        guard let data = try credentials.data(for: Self.credentialKey) else {
            throw GitHubAuthenticationError.reauthorizationRequired
        }
        do {
            let pair = try JSONDecoder().decode(GitHubTokenPair.self, from: data)
            cachedPair = pair
            return pair
        } catch {
            throw GitHubAuthenticationError.corruptCredentials
        }
    }

    private func persist(_ pair: GitHubTokenPair) throws {
        let data = try JSONEncoder().encode(pair)
        try credentials.set(data, for: Self.credentialKey)
        cachedPair = pair
    }

    private func requireClientID() throws {
        guard !configuration.clientID.isEmpty else {
            throw GitHubAuthenticationError.missingClientID
        }
    }
}

public enum GitHubAuthenticationError: LocalizedError, Equatable, Sendable {
    case missingClientID
    case invalidResponse
    case httpStatus(Int)
    case expired
    case accessDenied
    case deviceFlowDisabled
    case incorrectClientID
    case invalidDeviceCode
    case reauthorizationRequired
    case corruptCredentials
    case provider(String)

    public var errorDescription: String? {
        switch self {
            case .missingClientID:
                "Patchlight needs its GitHub App client ID before it can connect."
            case .invalidResponse:
                "GitHub returned an invalid authorization response."
            case let .httpStatus(status):
                "GitHub authorization failed with HTTP \(status)."
            case .expired:
                "The GitHub device code expired. Start again to get a new code."
            case .accessDenied:
                "GitHub authorization was cancelled."
            case .deviceFlowDisabled:
                "Device flow is not enabled for the Patchlight GitHub App."
            case .incorrectClientID:
                "The configured Patchlight GitHub App client ID is invalid."
            case .invalidDeviceCode:
                "GitHub rejected the device code. Start authorization again."
            case .reauthorizationRequired:
                "Your GitHub authorization expired. Reconnect to keep local drafts."
            case .corruptCredentials:
                "The stored GitHub credentials are unreadable. Reconnect to GitHub."
            case let .provider(code):
                "GitHub authorization failed (\(code))."
        }
    }
}

private enum GitHubEndpoint {
    static let deviceCode = URL(string: "https://github.com/login/device/code")!
    static let deviceVerification = URL(string: "https://github.com/login/device")!
    static let oauthToken = URL(string: "https://github.com/login/oauth/access_token")!
    static let oauthHeaders = [
        "Accept": "application/json",
        "Content-Type": "application/x-www-form-urlencoded",
    ]
}

private enum FormEncoding {
    static func encode(_ values: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let value = values.keys.sorted().map { key in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let rawValue = values[key] ?? ""
            let encodedValue = rawValue
                .addingPercentEncoding(withAllowedCharacters: allowed) ?? rawValue
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
        return Data(value.utf8)
    }
}

private struct DeviceAuthorizationWire: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct TokenWire: Decodable {
    let accessToken: String?
    let expiresIn: Int?
    let refreshToken: String?
    let refreshTokenExpiresIn: Int?
    let error: String?
    let interval: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case refreshTokenExpiresIn = "refresh_token_expires_in"
        case error
        case interval
    }
}

private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
    do {
        return try JSONDecoder().decode(type, from: data)
    } catch {
        throw GitHubAuthenticationError.invalidResponse
    }
}
