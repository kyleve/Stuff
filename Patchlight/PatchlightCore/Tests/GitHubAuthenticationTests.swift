import Foundation
@_spi(Testing) import PatchlightCore
@_spi(Testing) import StuffCore
import Testing

struct GitHubAuthenticationTests {
    private let configuration = GitHubAppConfiguration(
        clientID: "Iv1.patchlight",
        appSlug: "patchlight",
    )

    @Test func deviceFlowHonorsPendingAndSlowDownBeforePersistingThePair() async throws {
        let timestamp = Date(timeIntervalSince1970: 1000)
        let transport = ScriptedHTTPTransport([
            .success(.json("""
            {
              "device_code": "device-secret",
              "user_code": "ABCD-EFGH",
              "verification_uri": "https://github.com/login/device",
              "expires_in": 900,
              "interval": 5
            }
            """)),
            .success(.json("{\"error\":\"authorization_pending\"}")),
            .success(.json("{\"error\":\"slow_down\",\"interval\":10}")),
            .success(.json("""
            {
              "access_token": "ghu_access",
              "expires_in": 28800,
              "refresh_token": "ghr_refresh",
              "refresh_token_expires_in": 15897600,
              "token_type": "bearer"
            }
            """)),
        ])
        let credentials = InMemoryCredentialStore()
        let sleeper = ImmediateSleeper()
        let manager = GitHubCredentialManager(
            configuration: configuration,
            credentials: credentials,
            transport: transport,
            sleeper: sleeper,
            now: { timestamp },
        )

        let challenge = try await manager.beginDeviceAuthorization()
        let token = try await manager.completeDeviceAuthorization(challenge)

        #expect(challenge.userCode == "ABCD-EFGH")
        #expect(challenge.verificationURL.absoluteString == "https://github.com/login/device")
        #expect(token == GitHubAccessToken(rawValue: "ghu_access"))
        #expect(await sleeper.capturedDurations() == [.seconds(5), .seconds(10)])

        let storedData = try credentials.data(for: GitHubCredentialManager.credentialKey)
        let stored = try #require(storedData)
        let pair = try JSONDecoder().decode(GitHubTokenPair.self, from: stored)
        #expect(pair.accessToken == "ghu_access")
        #expect(pair.refreshToken == "ghr_refresh")

        let requests = await transport.capturedRequests()
        #expect(requests.count == 4)
        #expect(requests.allSatisfy { $0.url.host == "github.com" })
        #expect(requests.compactMap(\.body)
            .allSatisfy { !String(decoding: $0, as: UTF8.self).contains("client_secret") })
    }

    @Test func refreshReplacesAccessAndSingleUseRefreshTokenTogether() async throws {
        let timestamp = Date(timeIntervalSince1970: 5000)
        let old = GitHubTokenPair(
            accessToken: "old-access",
            accessTokenExpiresAt: timestamp.addingTimeInterval(-1),
            refreshToken: "old-refresh",
            refreshTokenExpiresAt: timestamp.addingTimeInterval(1000),
        )
        let credentials = try InMemoryCredentialStore(values: [
            GitHubCredentialManager.credentialKey: JSONEncoder().encode(old),
        ])
        let transport = ScriptedHTTPTransport([
            .success(.json("""
            {
              "access_token": "new-access",
              "expires_in": 28800,
              "refresh_token": "new-refresh",
              "refresh_token_expires_in": 15897600
            }
            """)),
        ])
        let manager = GitHubCredentialManager(
            configuration: configuration,
            credentials: credentials,
            transport: transport,
            sleeper: ImmediateSleeper(),
            now: { timestamp },
        )

        #expect(try await manager.accessToken() == GitHubAccessToken(rawValue: "new-access"))
        let storedData = try credentials.data(for: GitHubCredentialManager.credentialKey)
        let stored = try #require(storedData)
        let pair = try JSONDecoder().decode(GitHubTokenPair.self, from: stored)
        #expect(pair.accessToken == "new-access")
        #expect(pair.refreshToken == "new-refresh")
    }

    @Test func authorizationExpiryKeepsTheFailureTyped() async throws {
        let timestamp = Date(timeIntervalSince1970: 1000)
        let transport = ScriptedHTTPTransport([
            .success(.json("""
            {
              "device_code": "device-secret",
              "user_code": "ABCD-EFGH",
              "verification_uri": "https://github.com/login/device",
              "expires_in": 0,
              "interval": 5
            }
            """)),
        ])
        let manager = GitHubCredentialManager(
            configuration: configuration,
            credentials: InMemoryCredentialStore(),
            transport: transport,
            sleeper: ImmediateSleeper(),
            now: { timestamp },
        )

        let challenge = try await manager.beginDeviceAuthorization()
        await #expect(throws: GitHubAuthenticationError.expired) {
            try await manager.completeDeviceAuthorization(challenge)
        }
    }
}
