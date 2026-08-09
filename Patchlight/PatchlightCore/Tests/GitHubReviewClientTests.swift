import Foundation
@_spi(Testing) import PatchlightCore
@_spi(Testing) import StuffCore
import Testing

struct GitHubReviewClientTests {
    @Test func conversationIncludesCommentsThreadsReviewsAndChecks() async throws {
        let oid = String(repeating: "a", count: 40)
        let transport = RoutingHTTPTransport { request in
            switch request.url.path {
                case "/repos/acme/widget/issues/19/comments":
                    .json("""
                    [{"id":1,"node_id":"IC_1","user":{"login":"sam"},
                      "body":"General note","created_at":"2026-08-09T01:00:00Z"}]
                    """)
                case "/repos/acme/widget/pulls/19/reviews":
                    .json("""
                    [{"node_id":"PRR_1","user":{"login":"lee"},"body":"Looks good",
                      "state":"APPROVED","submitted_at":"2026-08-09T01:01:00Z"}]
                    """)
                case "/graphql":
                    .json("""
                    {"data":{"repository":{"pullRequest":{
                      "headRefOid":"\(oid)",
                      "reviewThreads":{"nodes":[{
                        "id":"PRRT_1","path":"Sources/App.swift","line":12,
                        "diffSide":"RIGHT","isOutdated":false,"isResolved":false,
                        "viewerCanResolve":true,"comments":{"nodes":[{
                          "id":"PRRC_1","databaseId":2,"body":"What about nil?",
                          "createdAt":"2026-08-09T01:02:00Z","author":{"login":"sam"}
                        }]}
                      }],"pageInfo":{"hasNextPage":false,"endCursor":null}},
                      "commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[
                        {"__typename":"CheckRun","name":"Tests","status":"COMPLETED",
                         "conclusion":"SUCCESS","detailsUrl":"https://github.com/acme/widget/actions"}
                      ]}}}}]}
                    }}}}
                    """)
                default:
                    .json("{\"message\":\"unexpected\"}", statusCode: 404)
            }
        }
        let client = makeClient(transport)

        let conversation = try await client.conversation(for: route)

        #expect(conversation.issueComments.first?.bodyMarkdown == "General note")
        #expect(conversation.reviews.first?.state == .approved)
        #expect(conversation.threads.first?.canResolve == true)
        #expect(conversation.threads.first?.comments.first?.databaseID?.rawValue == 2)
        #expect(conversation.checks == [CheckSummary(
            name: "Tests",
            state: .success,
            detailsURL: URL(string: "https://github.com/acme/widget/actions"),
        )])
    }

    @Test func reviewSubmissionBatchesAnchoredDraftsOnce() async throws {
        let transport = RoutingHTTPTransport { request in
            #expect(request.url.path == "/repos/acme/widget/pulls/19/reviews")
            #expect(request.method == .post)
            let body = try String(decoding: #require(request.body), as: UTF8.self)
            #expect(body.contains("REQUEST_CHANGES"))
            #expect(body.contains("Sources\\/Auth.swift"))
            #expect(body.contains("token rotation"))
            return .json(
                "{\"node_id\":\"PRR_result\"}",
                headers: ["x-github-request-id": "request-1"],
            )
        }
        let client = makeClient(transport)
        let head = PatchlightCoreTestSupport.objectID()
        let draft = ReviewDraft(
            id: UUID(),
            pullRequest: route.id,
            anchor: DiffAnchor(
                path: "Sources/Auth.swift",
                side: .head,
                commitOID: head,
                blobOID: nil,
                line: 9,
                startLine: nil,
                contextFingerprint: "context",
            ),
            body: "Please guard token rotation",
            updatedAt: Date(),
        )

        let receipt = try await client.submit(ReviewSubmission(
            pullRequest: route,
            headOID: head,
            event: .requestChanges,
            summary: "One blocker",
            drafts: [draft],
        ))

        #expect(receipt.nodeID?.rawValue == "PRR_result")
        #expect(receipt.requestID == "request-1")
        #expect(await transport.capturedRequests().count == 1)
    }

    @Test func ambiguousTransportFailureIsNeverRetried() async {
        let transport = ScriptedHTTPTransport([.failure(URLError(.networkConnectionLost))])
        let client = makeClient(transport)

        await #expect(throws: GitHubReviewWriteError.submissionStatusUncertain(requestID: nil)) {
            try await client.postConversationComment("Sent?", in: route)
        }
        #expect(await transport.capturedRequests().count == 1)
    }

    private var route: PullRequestRoute {
        PullRequestRoute(
            id: PatchlightCoreTestSupport.pullRequestID,
            repository: RepositoryCoordinates(owner: "acme", name: "widget"),
        )
    }

    private func makeClient(_ transport: any PatchlightHTTPTransport) -> GitHubReviewClient {
        let credentials = GitHubCredentialManager(
            configuration: GitHubAppConfiguration(clientID: "test", appSlug: "patchlight"),
            credentials: InMemoryCredentialStore(),
            transport: transport,
            sleeper: ImmediateSleeper(),
            now: Date.init,
            debugPersonalAccessToken: GitHubAccessToken(rawValue: "github_pat_test"),
        )
        return GitHubReviewClient(credentials: credentials, transport: transport)
    }
}
