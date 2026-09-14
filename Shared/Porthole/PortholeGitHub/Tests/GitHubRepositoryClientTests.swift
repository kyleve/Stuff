import Foundation
import PortholeGitHub
import Testing

struct GitHubRepositoryClientTests {
    @Test(arguments: [1, 2, 3, 4, 5, 6])
    func publicationNeverDispatchesUnderAReplacementAccount(switchAfterRequest: Int) async throws {
        let proposal = try GitHubTestFixtures.proposal()
        let steps = try GitHubRepositoryClientTestSupport.publicationSteps(proposal: proposal)
        let transport =
            GitHubScriptedTransport(Array(steps.prefix(switchAfterRequest)) + [.response(
                404,
                "",
            )])
        let credentials = try await GitHubMemoryCredentialStore.authenticated()
        let switching = try GitHubCredentialSwitchingTransport(
            transport: transport,
            credentials: credentials,
            clientID: GitHubTestFixtures.clientID,
            replacement: GitHubCredential(
                account: .init(userID: 456, login: "replacement-user"),
                accessToken: "replacement-token",
                expiresAt: nil,
            ),
            switchAfterRequest: switchAfterRequest,
        )
        let client = try GitHubRepositoryClient(
            clientID: GitHubTestFixtures.clientID,
            transport: switching,
            credentials: credentials,
            now: { GitHubTestFixtures.now },
        )
        let publisher = GitHubPublisher(remote: client)
        await #expect(throws: (any Error).self) { try await publisher.publish(proposal) }
        let publicationRequests = await transport.requests
        #expect(publicationRequests.count == switchAfterRequest)
        #expect(publicationRequests.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-test-token"
        })
        // Publication authorization is task-scoped. A later independent read may use the new
        // account.
        #expect(try await client
            .branchHead(repository: proposal.base.repository, branch: "main") == nil)
        #expect(await transport.requests.last?
            .value(forHTTPHeaderField: "Authorization") == "Bearer replacement-token")
    }

    @Test func publicationAcceptsARefreshedTokenForTheReviewedAccount() async throws {
        let proposal = try GitHubTestFixtures.proposal()
        let transport = try GitHubScriptedTransport(GitHubRepositoryClientTestSupport
            .publicationSteps(proposal: proposal))
        let credentials = try await GitHubMemoryCredentialStore.authenticated()
        let switching = try GitHubCredentialSwitchingTransport(
            transport: transport,
            credentials: credentials,
            clientID: GitHubTestFixtures.clientID,
            replacement: GitHubCredential(
                account: proposal.author,
                accessToken: "refreshed-token",
                expiresAt: nil,
            ),
            switchAfterRequest: 2,
        )
        let client = try GitHubRepositoryClient(
            clientID: GitHubTestFixtures.clientID,
            transport: switching,
            credentials: credentials,
            now: { GitHubTestFixtures.now },
        )
        let result = try await GitHubPublisher(remote: client).publish(proposal)
        #expect(try result.commit == GitHubTestFixtures.publishedCommit)
        let requests = await transport.requests
        #expect(requests.count == 7)
        #expect(requests.prefix(2).allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-test-token"
        })
        #expect(requests.dropFirst(2).allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == "Bearer refreshed-token"
        })
    }

    @Test func additionalFilesUseSavedTreeAfterTheBranchAdvances() async throws {
        let tree = #"{"tree":[{"path":"source.swift","mode":"100644","type":"blob","sha":"cccccccccccccccccccccccccccccccccccccccc","size":4}],"truncated":false}"#
        let transport = GitHubScriptedTransport([
            .response(
                200,
                #"{"sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","commit":{"tree":{"sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}}}"#,
            ),
            .response(200, tree),
            .response(200, #"{"object":{"sha":"dddddddddddddddddddddddddddddddddddddddd"}}"#),
            .response(200, tree),
            .response(200, #"{"content":"eHl6Cg==","encoding":"base64"}"#),
        ])
        let client = try await makeClient(transport)
        let reader: any GitHubRepositoryReading = client
        let base = try await reader.snapshot(
            repository: GitHubTestFixtures.repository,
            branch: "main",
            paths: [],
            maximumFileBytes: 1000,
        )
        let currentHead = try await client.branchHead(
            repository: base.repository,
            branch: base.branch,
        )
        #expect(currentHead != base.commit)
        let path = try GitHubRepositoryPath("source.swift")
        let selected = try await reader.snapshot(base: base, paths: [path], maximumFileBytes: 1000)
        #expect(selected.repository == base.repository)
        #expect(selected.branch == base.branch)
        #expect(selected.commit == base.commit)
        #expect(selected.tree == base.tree)
        #expect(selected.knownPaths == base.knownPaths)
        #expect(selected.files == [.init(path: path, text: "xyz\n", mode: .regular)])
        let requests = await transport.requests
        #expect(requests.map { $0.url?.path } == [
            "/repos/sample-user/Example/commits/main",
            "/repos/sample-user/Example/git/trees/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            "/repos/sample-user/Example/git/ref/heads/main",
            "/repos/sample-user/Example/git/trees/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            "/repos/sample-user/Example/git/blobs/cccccccccccccccccccccccccccccccccccccccc",
        ])
        #expect(requests[3].url?.query == "recursive=1")
    }

    @Test func fixedBaseRejectsTruncatedTrees() async throws {
        let base = try GitHubTestFixtures.workspace().repositoryBase
        let transport = GitHubScriptedTransport([
            .response(200, #"{"tree":[],"truncated":true}"#),
        ])
        let client = try await makeClient(transport)
        await #expect(throws: GitHubError.incompleteRepositoryTree) {
            try await client.snapshot(base: base, paths: [], maximumFileBytes: 1000)
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func fixedBaseRejectsChangedPathInventory() async throws {
        let base = try GitHubTestFixtures.workspace().repositoryBase
        let transport = GitHubScriptedTransport([
            .response(200, #"{"tree":[],"truncated":false}"#),
        ])
        let client = try await makeClient(transport)
        await #expect(throws: GitHubError.branchConflict) {
            try await client.snapshot(base: base, paths: [], maximumFileBytes: 1000)
        }
        #expect(await transport.requests.count == 1)
    }

    @Test(arguments: [false, true])
    func fixedBaseKeepsDeclaredAndDecodedFileLimits(oversizedMetadata: Bool) async throws {
        let base = try GitHubTestFixtures.workspace().repositoryBase
        let size = oversizedMetadata ? 4 : 1
        let transport = GitHubScriptedTransport([
            .response(200, """
            {
              "tree": [{
                "path": "Sources/Example.swift",
                "mode": "100644",
                "type": "blob",
                "sha": "cccccccccccccccccccccccccccccccccccccccc",
                "size": \(size)
              }],
              "truncated": false
            }
            """),
            .response(200, #"{"content":"eHl6Cg==","encoding":"base64"}"#),
        ])
        let client = try await makeClient(transport)
        await #expect(throws: GitHubError.fileTooLarge) {
            try await client.snapshot(
                base: base,
                paths: [GitHubRepositoryPath("Sources/Example.swift")],
                maximumFileBytes: 3,
            )
        }
        #expect(await transport.requests.count == (oversizedMetadata ? 1 : 2))
    }

    @Test func rejectsTruncatedTreesBeforeEditingFiles() async throws {
        let transport = GitHubScriptedTransport([
            .response(
                200,
                #"{"sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","commit":{"tree":{"sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}}}"#,
            ),
            .response(200, #"{"tree":[],"truncated":true}"#),
        ])
        let client = try await makeClient(transport)
        await #expect(throws: GitHubError.incompleteRepositoryTree) {
            try await client.snapshot(
                repository: GitHubTestFixtures.repository,
                branch: "main",
                paths: [],
                maximumFileBytes: 1000,
            )
        }
        #expect(await transport.requests.count == 2)
    }

    @Test func loadsTextFromImmutableCommitTree() async throws {
        let transport = GitHubScriptedTransport([
            .response(
                200,
                #"{"sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","commit":{"tree":{"sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}}}"#,
            ),
            .response(
                200,
                #"{"tree":[{"path":"source.swift","mode":"100644","type":"blob","sha":"cccccccccccccccccccccccccccccccccccccccc","size":4}],"truncated":false}"#,
            ),
            .response(200, #"{"content":"eHl6Cg==","encoding":"base64"}"#),
        ])
        let client = try await makeClient(transport)
        let path = try GitHubRepositoryPath("source.swift")
        let snapshot = try await client.snapshot(
            repository: GitHubTestFixtures.repository,
            branch: "main",
            paths: [path],
            maximumFileBytes: 1000,
        )
        #expect(snapshot.files.first?.text == "xyz\n")
        #expect(snapshot.knownPaths == [path])
        let requests = await transport.requests
        #expect(requests[2].url?.path
            .hasSuffix("/git/blobs/cccccccccccccccccccccccccccccccccccccccc") == true)
        #expect(requests
            .allSatisfy {
                $0.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-test-token"
            })
    }

    @Test func commitRetriesUseIdenticalAuthorDateAndTree() async throws {
        let base = #"{"tree":{"sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}}"#
        let tree = #"{"sha":"dddddddddddddddddddddddddddddddddddddddd"}"#
        let commit = #"{"sha":"cccccccccccccccccccccccccccccccccccccccc"}"#
        let transport = GitHubScriptedTransport([
            .response(200, base),
            .response(201, tree),
            .response(201, commit),
            .response(200, base),
            .response(201, tree),
            .response(201, commit),
        ])
        let client = try await makeClient(transport)
        let proposal = try GitHubTestFixtures.proposal()
        let first = try await client.createCommit(for: proposal)
        let second = try await client.createCommit(for: proposal)
        #expect(first == second)
        let requests = await transport.requests
        let firstBody = try #require(requests[2].httpBody)
        let secondBody = try #require(requests[5].httpBody)
        let firstObject = try #require(JSONSerialization
            .jsonObject(with: firstBody) as? NSDictionary)
        let secondObject = try #require(JSONSerialization
            .jsonObject(with: secondBody) as? NSDictionary)
        #expect(firstObject == secondObject)
        #expect(firstObject["author"] != nil)
        #expect(firstObject["committer"] != nil)
    }

    @Test func deletionUsesExplicitNullAndPreservesBaseTree() async throws {
        var workspace = try GitHubTestFixtures.workspace()
        try workspace.remove(at: GitHubRepositoryPath("Sources/Example.swift"))
        let proposal = try GitHubPullRequestProposal(
            proposalID: UUID(),
            workspace: workspace,
            title: "Remove source",
            body: "",
            evidence: .synthetic,
            author: GitHubTestFixtures.account,
            createdAt: GitHubTestFixtures.now,
        )
        let transport = GitHubScriptedTransport([
            .response(200, #"{"tree":{"sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}}"#),
            .response(201, #"{"sha":"dddddddddddddddddddddddddddddddddddddddd"}"#),
            .response(201, #"{"sha":"cccccccccccccccccccccccccccccccccccccccc"}"#),
        ])
        let client = try await makeClient(transport)
        _ = try await client.createCommit(for: proposal)
        let requests = await transport.requests
        let body = try #require(requests[1].httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let entries = try #require(object["tree"] as? [[String: Any]])
        #expect(object["base_tree"] as? String == "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
        #expect(entries.first?["sha"] is NSNull)
    }

    @Test func expiredCredentialNeverReachesTransport() async throws {
        let credentials = GitHubMemoryCredentialStore()
        let clientID = try GitHubTestFixtures.clientID
        await credentials.save(
            GitHubCredential(
                account: GitHubTestFixtures.account,
                accessToken: "expired",
                expiresAt: GitHubTestFixtures.now,
            ),
            for: clientID,
        )
        let transport = GitHubScriptedTransport([])
        let client = GitHubRepositoryClient(
            clientID: clientID,
            transport: transport,
            credentials: credentials,
            now: { GitHubTestFixtures.now },
        )
        await #expect(throws: GitHubError.credentialExpired) { try await client.branchHead(
            repository: GitHubTestFixtures.repository,
            branch: "main",
        ) }
        #expect(await transport.requests.isEmpty)
    }

    private func makeClient(_ transport: GitHubScriptedTransport) async throws
        -> GitHubRepositoryClient
    {
        try await GitHubRepositoryClient(
            clientID: GitHubTestFixtures.clientID,
            transport: transport,
            credentials: GitHubMemoryCredentialStore.authenticated(),
            now: { GitHubTestFixtures.now },
        )
    }
}
