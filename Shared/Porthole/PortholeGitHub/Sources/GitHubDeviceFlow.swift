import Foundation

/// GitHub App device flow. The caller schedules polls at `nextPollAt`; no timer survives its UI.
public actor GitHubDeviceFlow {
    public struct Authorization: Sendable, Equatable {
        public let userCode: String
        public let verificationURL: URL
        public let expiresAt: Date
        public let nextPollAt: Date
    }

    public enum PollResult: Sendable, Equatable {
        case waiting(Authorization)
        case authorized(GitHubAccount)
    }

    private struct Pending {
        let deviceCode: String
        let userCode: String
        let verificationURL: URL
        let expiresAt: Date
        var interval: TimeInterval
        var nextPollAt: Date

        var authorization: Authorization {
            Authorization(
                userCode: userCode,
                verificationURL: verificationURL,
                expiresAt: expiresAt,
                nextPollAt: nextPollAt,
            )
        }
    }

    private let clientID: GitHubClientID
    private let transport: any GitHubHTTPTransport
    private let credentials: any GitHubCredentialStore
    private var pending: Pending?
    private var isBusy = false
    private var cancelled = false

    public init(
        clientID: GitHubClientID,
        transport: any GitHubHTTPTransport,
        credentials: any GitHubCredentialStore,
    ) {
        self.clientID = clientID
        self.transport = transport
        self.credentials = credentials
    }

    public func begin(at now: Date) async throws -> Authorization {
        guard !isBusy else { throw GitHubError.busy }
        isBusy = true
        cancelled = false
        pending = nil
        defer { isBusy = false }
        struct Code: Decodable {
            let device_code: String
            let user_code: String
            let verification_uri: URL
            let expires_in: TimeInterval
            let interval: TimeInterval
        }
        let response = try await post(path: "device/code", fields: ["client_id": clientID.rawValue])
        try checkCancellation()
        let code = try JSONDecoder().decode(Code.self, from: response.body)
        guard code.verification_uri.scheme == "https", code.verification_uri.host == "github.com",
              code.expires_in > 0, code.interval > 0 else { throw GitHubError.invalidResponse }
        let value = Pending(
            deviceCode: code.device_code,
            userCode: code.user_code,
            verificationURL: code.verification_uri,
            expiresAt: now.addingTimeInterval(code.expires_in),
            interval: code.interval,
            nextPollAt: now.addingTimeInterval(code.interval),
        )
        pending = value
        return value.authorization
    }

    public func poll(at now: Date) async throws -> PollResult {
        guard !isBusy else { throw GitHubError.busy }
        guard var value = pending else { throw GitHubError.noAuthorization }
        guard now < value.expiresAt else {
            pending = nil
            throw GitHubError.authorizationExpired
        }
        guard now >= value.nextPollAt else { return .waiting(value.authorization) }
        isBusy = true
        defer { isBusy = false }
        // Reserve the next slot before suspension, including transport failures.
        value.nextPollAt = now.addingTimeInterval(value.interval)
        pending = value
        let response = try await post(path: "oauth/access_token", fields: [
            "client_id": clientID.rawValue,
            "device_code": value.deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ])
        try checkCancellation()
        struct Token: Decodable {
            let access_token: String?
            let token_type: String?
            let expires_in: TimeInterval?
            let error: String?
            let interval: TimeInterval?
        }
        let token = try JSONDecoder().decode(Token.self, from: response.body)
        if let error = token.error {
            switch error {
                case "authorization_pending": return .waiting(value.authorization)
                case "slow_down":
                    value.interval = max(value.interval + 5, token.interval ?? 0)
                    value.nextPollAt = now.addingTimeInterval(value.interval)
                    pending = value
                    return .waiting(value.authorization)
                case "expired_token", "token_expired":
                    pending = nil
                    throw GitHubError.authorizationExpired
                case "access_denied":
                    pending = nil
                    throw GitHubError.authorizationDenied
                case "device_flow_disabled", "incorrect_client_credentials",
                     "incorrect_device_code",
                     "unsupported_grant_type":
                    pending = nil
                    throw GitHubError.authorizationFailed(code: error)
                default:
                    pending = nil
                    throw GitHubError.authorizationFailed(code: "unknown_error")
            }
        }
        guard let accessToken = token.access_token, !accessToken.isEmpty,
              token.token_type?.lowercased() == "bearer"
        else {
            throw GitHubError.invalidResponse
        }
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Porthole", forHTTPHeaderField: "User-Agent")
        let identityResponse = try await transport.send(request)
        try checkCancellation()
        guard identityResponse.statusCode == 200
        else { throw GitHubError.requestFailed(statusCode: identityResponse.statusCode) }
        struct Identity: Decodable { let id: Int; let login: String }
        let identity = try JSONDecoder().decode(Identity.self, from: identityResponse.body)
        let account = GitHubAccount(userID: identity.id, login: identity.login)
        try await credentials.save(GitHubCredential(
            account: account,
            accessToken: accessToken,
            expiresAt: token.expires_in.map { now.addingTimeInterval($0) },
        ), for: clientID)
        if cancelled || Task.isCancelled {
            try await credentials.remove(for: clientID)
            throw CancellationError()
        }
        pending = nil
        return .authorized(account)
    }

    public func cancel() {
        cancelled = true
        pending = nil
    }

    public func signOut() async throws {
        guard !isBusy else { throw GitHubError.busy }
        isBusy = true
        defer { isBusy = false }
        cancel()
        try await credentials.remove(for: clientID)
    }

    private func checkCancellation() throws {
        if cancelled { throw CancellationError() }
        try Task.checkCancellation()
    }

    private func post(path: String, fields: [String: String]) async throws -> GitHubHTTPResponse {
        var request = URLRequest(url: URL(string: "https://github.com/login/\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(fields)
        let response = try await transport.send(request)
        guard response.statusCode == 200
        else { throw GitHubError.requestFailed(statusCode: response.statusCode) }
        return response
    }
}
