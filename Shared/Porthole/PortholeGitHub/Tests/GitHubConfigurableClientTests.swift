import Foundation
@testable import PortholeGitHub
import Testing

struct GitHubConfigurableClientTests {
    @Test func configuredClientLoadsAdditionalFilesFromTheSavedTree() async throws {
        let base = try GitHubTestFixtures.workspace().repositoryBase
        let transport = GitHubScriptedTransport([
            .response(
                200,
                #"{"tree":[{"path":"Sources/Example.swift","mode":"100644","type":"blob","sha":"cccccccccccccccccccccccccccccccccccccccc","size":4}],"truncated":false}"#,
            ),
            .response(200, #"{"content":"eHl6Cg==","encoding":"base64"}"#),
        ])
        let client = try await GitHubConfigurableClient(
            clientID: GitHubTestFixtures.clientID,
            configurationURL: nil,
            transport: transport,
            credentials: GitHubMemoryCredentialStore.authenticated(),
        )
        let selected = try await client.snapshot(
            base: base,
            paths: [GitHubRepositoryPath("Sources/Example.swift")],
            maximumFileBytes: 1000,
        )
        #expect(selected.commit == base.commit)
        #expect(selected.tree == base.tree)
        #expect(selected.files.first?.text == "xyz\n")
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.first?.url?.path.hasSuffix("/git/trees/" + base.tree.rawValue) == true)
    }

    @Test func unconfiguredClientMakesNoRequestAndPersistsOnlyPublicClientID() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
        }
        let url = directory.appending(path: "github-client-id.json")
        let transport = GitHubScriptedTransport([])
        let credentials = GitHubMemoryCredentialStore()
        let client = try GitHubConfigurableClient(
            clientID: nil,
            configurationURL: url,
            transport: transport,
            credentials: credentials,
        )
        await #expect(throws: GitHubError.invalidIdentifier) { try await client.account() }
        #expect(await transport.requests.isEmpty)
        try await client.configure(clientID: GitHubTestFixtures.clientID)
        let stored = try String(contentsOf: url, encoding: .utf8)
        #expect(stored.contains("Iv1.test"))
        #expect(!stored.contains("accessToken"))
        let restored = try GitHubConfigurableClient(
            clientID: nil,
            configurationURL: url,
            transport: transport,
            credentials: credentials,
        )
        #expect(try await restored.configuredClientID() == GitHubTestFixtures.clientID)
        await #expect(throws: GitHubError.unauthenticated) { try await restored.account() }
        #expect(await transport.requests.isEmpty)
    }
}
