import Foundation
import PortholeGitHub
import Testing

struct GitHubDeviceFlowTests {
    private static let code = #"{"device_code":"private-device-code","user_code":"ABCD-EFGH","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#

    @Test func respectsPollingIntervalAndSlowDown() async throws {
        let transport = GitHubScriptedTransport([
            .response(200, Self.code),
            .response(200, #"{"error":"slow_down","interval":10}"#),
            .response(200, #"{"error":"authorization_pending"}"#),
        ])
        let flow = try GitHubDeviceFlow(
            clientID: GitHubTestFixtures.clientID,
            transport: transport,
            credentials: GitHubMemoryCredentialStore(),
        )
        let now = GitHubTestFixtures.now
        let authorization = try await flow.begin(at: now)
        #expect(authorization.nextPollAt == now.addingTimeInterval(5))
        _ = try await flow.poll(at: now.addingTimeInterval(4))
        #expect(await transport.requests.count == 1)
        let slowed = try await flow.poll(at: now.addingTimeInterval(5))
        guard case let .waiting(updated) = slowed
        else { Issue.record("Expected a pending authorization"); return }
        #expect(updated.nextPollAt == now.addingTimeInterval(15))
        _ = try await flow.poll(at: now.addingTimeInterval(14))
        #expect(await transport.requests.count == 2)
        _ = try await flow.poll(at: now.addingTimeInterval(15))
        #expect(await transport.requests.count == 3)
    }

    @Test func validatesIdentityBeforeSavingCredential() async throws {
        let transport = GitHubScriptedTransport([
            .response(200, Self.code),
            .response(
                200,
                #"{"access_token":"synthetic-token","token_type":"bearer","expires_in":3600}"#,
            ),
            .response(200, #"{"id":123,"login":"sample-user"}"#),
        ])
        let credentials = GitHubMemoryCredentialStore()
        let clientID = try GitHubTestFixtures.clientID
        let flow = GitHubDeviceFlow(
            clientID: clientID,
            transport: transport,
            credentials: credentials,
        )
        _ = try await flow.begin(at: GitHubTestFixtures.now)
        let result = try await flow.poll(at: GitHubTestFixtures.now.addingTimeInterval(5))
        #expect(result == .authorized(GitHubTestFixtures.account))
        #expect(await credentials.credential(for: clientID)?.account == GitHubTestFixtures.account)
        let requests = await transport.requests
        #expect(requests[2].url?.path == "/user")
        #expect(requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-token")
        try await flow.signOut()
        #expect(await credentials.credential(for: clientID) == nil)
    }

    @Test func failedIdentityDoesNotStoreToken() async throws {
        let transport = GitHubScriptedTransport([
            .response(200, Self.code),
            .response(200, #"{"access_token":"synthetic-token","token_type":"bearer"}"#),
            .response(401, "{}"),
        ])
        let credentials = GitHubMemoryCredentialStore()
        let clientID = try GitHubTestFixtures.clientID
        let flow = GitHubDeviceFlow(
            clientID: clientID,
            transport: transport,
            credentials: credentials,
        )
        _ = try await flow.begin(at: GitHubTestFixtures.now)
        await #expect(throws: GitHubError.requestFailed(statusCode: 401)) {
            try await flow.poll(at: GitHubTestFixtures.now.addingTimeInterval(5))
        }
        #expect(await credentials.credential(for: clientID) == nil)
    }

    @Test func expiryAndCancellationStopRequests() async throws {
        let transport = GitHubScriptedTransport([.response(200, Self.code)])
        let flow = try GitHubDeviceFlow(
            clientID: GitHubTestFixtures.clientID,
            transport: transport,
            credentials: GitHubMemoryCredentialStore(),
        )
        _ = try await flow.begin(at: GitHubTestFixtures.now)
        await #expect(throws: GitHubError.authorizationExpired) {
            try await flow.poll(at: GitHubTestFixtures.now.addingTimeInterval(900))
        }
        await flow.cancel()
        await #expect(throws: GitHubError.noAuthorization) {
            try await flow.poll(at: GitHubTestFixtures.now)
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func transportFailureStillReservesPollingInterval() async throws {
        let transport = GitHubScriptedTransport([.response(200, Self.code), .disconnected])
        let flow = try GitHubDeviceFlow(
            clientID: GitHubTestFixtures.clientID,
            transport: transport,
            credentials: GitHubMemoryCredentialStore(),
        )
        _ = try await flow.begin(at: GitHubTestFixtures.now)
        await #expect(throws: GitHubScriptedTransport.Failure.disconnected) {
            try await flow.poll(at: GitHubTestFixtures.now.addingTimeInterval(5))
        }
        _ = try await flow.poll(at: GitHubTestFixtures.now.addingTimeInterval(6))
        #expect(await transport.requests.count == 2)
    }
}
