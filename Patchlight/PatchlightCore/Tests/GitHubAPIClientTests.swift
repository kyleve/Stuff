import Foundation
@_spi(Testing) import PatchlightCore
@_spi(Testing) import StuffCore
import Testing

struct GitHubAPIClientTests {
    private func makeClient(transport: any PatchlightHTTPTransport) -> GitHubAPIClient {
        let credentials = GitHubCredentialManager(
            configuration: GitHubAppConfiguration(clientID: "test", appSlug: "patchlight"),
            credentials: InMemoryCredentialStore(),
            transport: transport,
            sleeper: ImmediateSleeper(),
            now: { Date() },
            debugPersonalAccessToken: GitHubAccessToken(rawValue: "github_pat_test"),
        )
        return GitHubAPIClient(credentials: credentials, transport: transport)
    }

    @Test func installationsStayGroupedAndExposeWithheldTeamDiscovery() async throws {
        let transport = RoutingHTTPTransport { request in
            switch request.url.path {
                case "/user/installations":
                    .json("""
                    {"installations":[{
                      "id":91,
                      "account":{"login":"acme","type":"Organization"},
                      "permissions":{"contents":"read","pull_requests":"write"}
                    }]}
                    """)
                case "/user/installations/91/repositories":
                    .json("""
                    {"repositories":[{
                      "id":7,"name":"widget","private":true,"default_branch":"main",
                      "owner":{"login":"acme"}
                    }]}
                    """)
                default:
                    .json("{\"message\":\"unexpected route\"}", statusCode: 404)
            }
        }
        let client = makeClient(transport: transport)

        let installations = try await client.installations()

        let installation = try #require(installations.first)
        #expect(installation.accountLogin == "acme")
        #expect(installation.teamDiscovery == .permissionWithheld)
        #expect(installation.repositories.first?.coordinates.displayName == "acme/widget")
        let requests = await transport.capturedRequests()
        #expect(requests.allSatisfy { $0.headers["X-GitHub-Api-Version"] == "2026-03-10" })
    }

    @Test func conditionalReadsReuseValidatedETagBodies() async throws {
        let calls = RequestCounter()
        let transport = RoutingHTTPTransport { request in
            let call = await calls.take()
            if call == 0 {
                return .json(
                    "{\"id\":42,\"login\":\"reviewer\",\"avatar_url\":null}",
                    headers: ["etag": "\"viewer-v1\""],
                )
            }
            #expect(request.headers["If-None-Match"] == "\"viewer-v1\"")
            return PatchlightHTTPResponse(statusCode: 304, headers: [:], body: Data())
        }
        let client = makeClient(transport: transport)

        #expect(try await client.viewer().login == "reviewer")
        #expect(try await client.viewer().login == "reviewer")
    }

    @Test func dashboardKeepsPartialGraphQLDataAndPermissionWarnings() async throws {
        let transport = RoutingHTTPTransport { request in
            switch request.url.path {
                case "/user":
                    .json("{\"id\":42,\"login\":\"reviewer\",\"avatar_url\":null}")
                case "/user/installations":
                    .json("""
                    {"installations":[{
                      "id":91,
                      "account":{"login":"acme","type":"Organization"},
                      "permissions":{"contents":"read"}
                    }]}
                    """)
                case "/user/installations/91/repositories":
                    .json("{\"repositories\":[]}")
                case "/graphql":
                    try graphQLDashboardResponse(for: request)
                default:
                    .json("{\"message\":\"unexpected route\"}", statusCode: 404)
            }
        }
        let client = makeClient(transport: transport)

        let dashboard = try await client.dashboard()

        #expect(dashboard.reviewRequests.count == 1)
        #expect(dashboard.reviewRequests.first?.reviewRequestSource == .direct)
        #expect(dashboard.ownPullRequests.first?.isDraft == true)
        #expect(dashboard.warnings.contains {
            $0.code == .teamDiscoveryUnavailable && $0.context == "acme"
        })
        #expect(dashboard.warnings.contains { $0.code == .partialGraphQLResponse })
        #expect(await transport.capturedRequests().allSatisfy { $0.url.path != "/user/teams" })
    }

    @Test func missingPatchUsesExactBaseAndHeadBlobsForLocalDiff() async throws {
        let baseCommit = String(repeating: "a", count: 40)
        let baseBlob = String(repeating: "b", count: 40)
        let headBlob = String(repeating: "c", count: 40)
        let headCommit = String(repeating: "d", count: 40)
        let transport = RoutingHTTPTransport { request in
            switch request.url.path {
                case "/repositories/7": return repositoryResponse()
                case "/repos/acme/widget/pulls/19":
                    return pullRequestResponse(base: baseCommit, head: headCommit, changedFiles: 1)
                case "/repos/acme/widget/pulls/19/files":
                    return .json("""
                    [{
                      "sha":"\(headBlob)","filename":"Sources/File.swift","status":"modified",
                      "additions":1,"deletions":1
                    }]
                    """)
                case "/repos/acme/widget/contents/Sources/File.swift":
                    #expect(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first?.value == baseCommit)
                    return .json("{\"type\":\"file\",\"sha\":\"\(baseBlob)\"}")
                case "/repos/acme/widget/git/blobs/\(baseBlob)":
                    return PatchlightHTTPResponse(
                        statusCode: 200,
                        headers: [:],
                        body: Data("one\ntwo\n".utf8),
                    )
                case "/repos/acme/widget/git/blobs/\(headBlob)":
                    return PatchlightHTTPResponse(
                        statusCode: 200,
                        headers: [:],
                        body: Data("one\nsecond\n".utf8),
                    )
                default:
                    return .json("{\"message\":\"unexpected route\"}", statusCode: 404)
            }
        }
        let client = makeClient(transport: transport)

        let workspace = try await client.workspace(for: PatchlightCoreTestSupport.pullRequestID)

        let file = try #require(workspace.files.first)
        #expect(workspace.isFileListComplete)
        #expect(file.availability == .complete)
        #expect(file.baseBlobOID?.rawValue == baseBlob)
        #expect(file.headBlobOID?.rawValue == headBlob)
        let containsSecond = file.hunks.first?.lines.contains {
            $0.kind == .addition && $0.text == "second"
        }
        #expect(containsSecond == true)
    }

    @Test func moreThanThreeThousandFilesIsAlwaysMarkedIncomplete() async throws {
        let base = String(repeating: "a", count: 40)
        let head = String(repeating: "b", count: 40)
        let transport = RoutingHTTPTransport { request in
            switch request.url.path {
                case "/repositories/7": repositoryResponse()
                case "/repos/acme/widget/pulls/19":
                    pullRequestResponse(base: base, head: head, changedFiles: 3001)
                case "/repos/acme/widget/pulls/19/files":
                    .json("""
                    [{
                      "sha":"\(head)","filename":"File.swift","status":"modified",
                      "additions":1,"deletions":1,"patch":"@@ -1 +1 @@\\n-old\\n+new"
                    }]
                    """)
                default:
                    .json("{\"message\":\"unexpected route\"}", statusCode: 404)
            }
        }
        let client = makeClient(transport: transport)

        let workspace = try await client.workspace(for: PatchlightCoreTestSupport.pullRequestID)

        #expect(!workspace.isFileListComplete)
        #expect(workspace.files.count == 1)
        #expect(workspace.files.first?.availability == .complete)
    }

    @Test func rateLimitsCarryTheServerResetTime() async {
        let transport = RoutingHTTPTransport { _ in
            .json(
                "{\"message\":\"API rate limit exceeded\"}",
                statusCode: 403,
                headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "2000"],
            )
        }
        let client = makeClient(transport: transport)

        await #expect(throws: GitHubAPIError.rateLimited(
            resetAt: Date(timeIntervalSince1970: 2000),
        )) {
            try await client.viewer()
        }
    }
}

private actor RequestCounter {
    private var value = 0

    func take() -> Int {
        defer { value += 1 }
        return value
    }
}

private func repositoryResponse() -> PatchlightHTTPResponse {
    .json("""
    {
      "id":7,"name":"widget","private":false,"default_branch":"main",
      "owner":{"login":"acme"},"installation_id":91
    }
    """)
}

private func pullRequestResponse(
    base: String,
    head: String,
    changedFiles: Int,
) -> PatchlightHTTPResponse {
    .json("""
    {
      "number":19,"title":"Improve review","user":{"login":"author"},"draft":false,
      "updated_at":"2026-08-08T20:00:00Z","changed_files":\(changedFiles),
      "base":{"sha":"\(base)","repo":{"id":7}},
      "head":{"sha":"\(head)","repo":{"id":7}}
    }
    """)
}

private func graphQLDashboardResponse(
    for request: PatchlightHTTPRequest,
) throws -> PatchlightHTTPResponse {
    let body = try String(decoding: #require(request.body), as: UTF8.self)
    let oid = String(repeating: "a", count: 40)
    if body.contains("PatchlightRequestedReviews") {
        return .json("""
        {
          "data":{"search":{
            "nodes":[{
              "number":3,"title":"Requested","isDraft":false,"headRefOid":"\(oid)",
              "updatedAt":"2026-08-08T20:00:00Z","author":{"login":"author"},
              "repository":{"databaseId":7,"name":"widget","owner":{"login":"acme"}}
            }],
            "pageInfo":{"hasNextPage":false,"endCursor":null}
          }},
          "errors":[{"message":"One organization hid optional review metadata"}]
        }
        """)
    }
    return .json("""
    {"data":{"viewer":{"pullRequests":{
      "nodes":[{
        "number":4,"title":"Mine","isDraft":true,"headRefOid":"\(oid)",
        "updatedAt":"2026-08-08T19:00:00Z","author":{"login":"reviewer"},
        "repository":{"databaseId":7,"name":"widget","owner":{"login":"acme"}}
      }],
      "pageInfo":{"hasNextPage":false,"endCursor":null}
    }}}}
    """)
}
