import Foundation
import PortholeGitHub

/// Replaces credentials between two real repository-client requests.
actor GitHubCredentialSwitchingTransport: GitHubHTTPTransport {
    private let transport: GitHubScriptedTransport
    private let credentials: GitHubMemoryCredentialStore
    private let clientID: GitHubClientID
    private let replacement: GitHubCredential
    private let switchAfterRequest: Int
    private var requestCount = 0

    init(
        transport: GitHubScriptedTransport,
        credentials: GitHubMemoryCredentialStore,
        clientID: GitHubClientID,
        replacement: GitHubCredential,
        switchAfterRequest: Int,
    ) {
        self.transport = transport
        self.credentials = credentials
        self.clientID = clientID
        self.replacement = replacement
        self.switchAfterRequest = switchAfterRequest
    }

    func send(_ request: URLRequest) async throws -> GitHubHTTPResponse {
        let response = try await transport.send(request)
        requestCount += 1
        if requestCount == switchAfterRequest {
            await credentials.save(replacement, for: clientID)
        }
        return response
    }
}

enum GitHubRepositoryClientTestSupport {
    static func publicationSteps(proposal: GitHubPullRequestProposal) throws
        -> [GitHubScriptedTransport.Step]
    {
        let pullRequest: [String: Any] = try [
            "number": 12,
            "html_url": "https://github.com/sample-user/Example/pull/12",
            "head": ["sha": GitHubTestFixtures.publishedCommit.rawValue],
            "base": ["ref": proposal.base.branch],
            "body": proposal.marker,
            "draft": true,
        ]
        let response = try JSONSerialization.data(withJSONObject: pullRequest, options: .sortedKeys)
        return [
            .response(200, #"{"tree":{"sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}}"#),
            .response(201, #"{"sha":"dddddddddddddddddddddddddddddddddddddddd"}"#),
            .response(201, #"{"sha":"cccccccccccccccccccccccccccccccccccccccc"}"#),
            .response(404, ""),
            .response(201, "{}"),
            .response(200, "[]"),
            .response(201, String(decoding: response, as: UTF8.self)),
        ]
    }
}
