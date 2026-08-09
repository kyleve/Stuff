import Foundation

/// Reads review discussion and performs explicit GitHub mutations. Each write
/// makes exactly one transport attempt; failures that could occur after bytes
/// leave the process are surfaced as uncertain instead of retried.
public actor GitHubReviewClient: GitHubReviewReading, GitHubReviewWriting {
    private let credentials: GitHubCredentialManager
    private let transport: any PatchlightHTTPTransport

    public init(
        credentials: GitHubCredentialManager,
        transport: any PatchlightHTTPTransport,
    ) {
        self.credentials = credentials
        self.transport = transport
    }

    public func conversation(
        for pullRequest: PullRequestRoute,
    ) async throws -> PullRequestConversation {
        let commentWires = try await paginated(
            IssueCommentWire.self,
            path: repositoryPath(pullRequest) + [
                "issues",
                String(pullRequest.id.number),
                "comments",
            ],
        )
        let reviewWires = try await paginated(
            ReviewWire.self,
            path: repositoryPath(pullRequest) + ["pulls", String(pullRequest.id.number), "reviews"],
        )
        let detail = try await conversationDetails(for: pullRequest)
        return try PullRequestConversation(
            pullRequest: pullRequest,
            headOID: GitObjectID(validating: detail.headRefOID),
            issueComments: commentWires.map(\.domainValue),
            reviews: reviewWires.map { try $0.domainValue },
            threads: detail.reviewThreads.nodes.map(\.domainValue),
            checks: detail.commits.nodes.last?.commit.statusCheckRollup?.contexts.nodes
                .compactMap(\.domainValue) ?? [],
        )
    }

    public func submit(_ review: ReviewSubmission) async throws -> ReviewWriteReceipt {
        let comments = try review.drafts.map { draft -> ReviewCommentBody in
            guard let anchor = draft.anchor else {
                throw GitHubReviewWriteError.invalidAnchor(draft.id)
            }
            guard anchor.commitOID == review.headOID else {
                throw GitHubReviewWriteError.staleHead(
                    expected: anchor.commitOID,
                    actual: review.headOID,
                )
            }
            return ReviewCommentBody(
                path: anchor.path,
                body: draft.body,
                line: anchor.line,
                side: anchor.line == nil ? nil : anchor.side.apiCode,
                startLine: anchor.startLine,
                startSide: anchor.startLine == nil ? nil : anchor.side.apiCode,
                subjectType: anchor.line == nil ? "file" : nil,
            )
        }
        let response = try await mutate(
            method: .post,
            path: repositoryPath(review.pullRequest) + [
                "pulls",
                String(review.pullRequest.id.number),
                "reviews",
            ],
            body: ReviewSubmissionBody(
                commitID: review.headOID.rawValue,
                body: review.summary,
                event: review.event.rawValue,
                comments: comments,
            ),
        )
        return try receipt(response)
    }

    public func postConversationComment(
        _ body: String,
        in pullRequest: PullRequestRoute,
    ) async throws -> ReviewWriteReceipt {
        let response = try await mutate(
            method: .post,
            path: repositoryPath(pullRequest) + [
                "issues",
                String(pullRequest.id.number),
                "comments",
            ],
            body: CommentBody(body: body),
        )
        return try receipt(response)
    }

    public func postFileComment(
        _ body: String,
        path: String,
        headOID: GitObjectID,
        in pullRequest: PullRequestRoute,
    ) async throws -> ReviewWriteReceipt {
        let response = try await mutate(
            method: .post,
            path: repositoryPath(pullRequest) + [
                "pulls",
                String(pullRequest.id.number),
                "comments",
            ],
            body: FileCommentBody(
                body: body,
                commitID: headOID.rawValue,
                path: path,
                subjectType: "file",
            ),
        )
        return try receipt(response)
    }

    public func reply(
        to commentID: GitHubCommentID,
        body: String,
        in pullRequest: PullRequestRoute,
    ) async throws -> ReviewWriteReceipt {
        let response = try await mutate(
            method: .post,
            path: repositoryPath(pullRequest) + [
                "pulls",
                "comments",
                String(commentID.rawValue),
                "replies",
            ],
            body: CommentBody(body: body),
        )
        return try receipt(response)
    }

    public func setThread(_ threadID: GitHubNodeID, resolved: Bool) async throws {
        let query = resolved ? Self.resolveThreadMutation : Self.unresolveThreadMutation
        let response = try await mutate(
            method: .post,
            path: ["graphql"],
            body: GraphQLRequestBody(
                query: query,
                variables: ThreadMutationVariables(threadID: threadID.rawValue),
            ),
        )
        let result = try decode(GraphQLMutationResponse.self, from: response.body)
        if let errors = result.errors, !errors.isEmpty {
            throw GitHubAPIError.graphQL(errors.map(\.message))
        }
    }

    public func markFile(
        _ path: String,
        viewed: Bool,
        in pullRequest: PullRequestRoute,
    ) async throws {
        _ = try await mutate(
            method: viewed ? .put : .delete,
            path: repositoryPath(pullRequest) + [
                "pulls",
                String(pullRequest.id.number),
                "files",
            ] + pathComponents(path),
            body: EmptyBody?.none,
        )
    }

    private func conversationDetails(
        for pullRequest: PullRequestRoute,
    ) async throws -> ConversationPullRequestWire {
        var cursor: String?
        var threads: [ReviewThreadWire] = []
        var firstPage: ConversationPullRequestWire?
        repeat {
            let response: GraphQLResponseWire<ConversationDataWire> = try await graphQL(
                query: Self.conversationQuery,
                variables: ConversationVariables(
                    owner: pullRequest.repository.owner,
                    name: pullRequest.repository.name,
                    number: pullRequest.id.number,
                    cursor: cursor,
                ),
            )
            if let errors = response.errors, !errors.isEmpty {
                throw GitHubAPIError.graphQL(errors.map(\.message))
            }
            guard let value = response.data?.repository.pullRequest else {
                throw GitHubAPIError.notFound
            }
            firstPage = firstPage ?? value
            threads.append(contentsOf: value.reviewThreads.nodes)
            cursor = value.reviewThreads.pageInfo?.hasNextPage == true
                ? value.reviewThreads.pageInfo?.endCursor
                : nil
        } while cursor != nil
        guard let value = firstPage else {
            throw GitHubAPIError.invalidResponse
        }
        return ConversationPullRequestWire(
            headRefOID: value.headRefOID,
            reviewThreads: ConnectionWire(
                nodes: threads,
                pageInfo: PageInfoWire(hasNextPage: false, endCursor: nil),
            ),
            commits: value.commits,
        )
    }

    private func graphQL<Payload: Decodable>(
        query: String,
        variables: some Encodable & Sendable,
    ) async throws -> GraphQLResponseWire<Payload> {
        let response = try await read(
            method: .post,
            path: ["graphql"],
            body: GraphQLRequestBody(query: query, variables: variables),
        )
        return try decode(GraphQLResponseWire<Payload>.self, from: response.body)
    }

    private func paginated<Value: Decodable>(
        _: Value.Type,
        path: [String],
    ) async throws -> [Value] {
        var page = 1
        var values: [Value] = []
        while true {
            let response = try await read(
                method: .get,
                path: path,
                query: [
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: String(page)),
                ],
                body: EmptyBody?.none,
            )
            let batch = try decode([Value].self, from: response.body)
            values.append(contentsOf: batch)
            if batch.count < 100 { return values }
            page += 1
        }
    }

    private func read(
        method: PatchlightHTTPMethod,
        path: [String],
        query: [URLQueryItem] = [],
        body: some Encodable & Sendable,
    ) async throws -> PatchlightHTTPResponse {
        let token = try await credentials.accessToken()
        let bodyData = try bodyData(body)
        let response = try await transport.send(PatchlightHTTPRequest(
            method: method,
            url: Self.apiURL(path: path, query: query),
            headers: Self.headers(token: token, hasBody: bodyData != nil),
            body: bodyData,
        ))
        guard (200 ... 299).contains(response.statusCode) else {
            throw Self.apiError(response)
        }
        return response
    }

    private func mutate(
        method: PatchlightHTTPMethod,
        path: [String],
        body: some Encodable & Sendable,
    ) async throws -> PatchlightHTTPResponse {
        let token = try await credentials.accessToken()
        let bodyData = try bodyData(body)
        let request = try PatchlightHTTPRequest(
            method: method,
            url: Self.apiURL(path: path, query: []),
            headers: Self.headers(token: token, hasBody: bodyData != nil),
            body: bodyData,
        )
        let response: PatchlightHTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            throw GitHubReviewWriteError.submissionStatusUncertain(requestID: nil)
        }
        if response.statusCode >= 500 {
            throw GitHubReviewWriteError.submissionStatusUncertain(
                requestID: response.header("x-github-request-id"),
            )
        }
        guard (200 ... 299).contains(response.statusCode) else {
            throw Self.apiError(response)
        }
        return response
    }

    private func bodyData<Body: Encodable>(_ body: Body) throws -> Data? {
        if Body.self == EmptyBody?.self { return nil }
        return try JSONEncoder().encode(body)
    }

    private func receipt(_ response: PatchlightHTTPResponse) throws -> ReviewWriteReceipt {
        let nodeID: GitHubNodeID?
        do {
            nodeID = try decode(NodeReceiptWire.self, from: response.body).nodeID
                .map(GitHubNodeID.init(rawValue:))
        } catch {
            // A 2xx status and request ID prove the write; some GitHub write
            // endpoints omit the optional GraphQL node identifier.
            nodeID = nil
        }
        return ReviewWriteReceipt(
            nodeID: nodeID,
            requestID: response.header("x-github-request-id"),
        )
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(type, from: data)
        } catch {
            throw GitHubAPIError.invalidResponse
        }
    }

    private func repositoryPath(_ pullRequest: PullRequestRoute) -> [String] {
        ["repos", pullRequest.repository.owner, pullRequest.repository.name]
    }

    private func pathComponents(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private static func headers(token: GitHubAccessToken, hasBody: Bool) -> [String: String] {
        var headers = [
            "Accept": "application/vnd.github+json",
            "Authorization": "Bearer \(token.rawValue)",
            "X-GitHub-Api-Version": "2026-03-10",
        ]
        if hasBody { headers["Content-Type"] = "application/json" }
        return headers
    }

    private static func apiURL(path: [String], query: [URLQueryItem]) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        components.percentEncodedPath = "/" + path.map {
            $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        }.joined(separator: "/")
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw GitHubAPIError.invalidRoute }
        return url
    }

    private static func apiError(_ response: PatchlightHTTPResponse) -> GitHubAPIError {
        let message: String?
        do {
            message = try JSONDecoder().decode(APIErrorWire.self, from: response.body).message
        } catch {
            message = nil
        }
        switch response.statusCode {
            case 401: return .authenticationExpired
            case 403: return .permissionDenied(message)
            case 404: return .notFound
            default: return .httpStatus(response.statusCode, message)
        }
    }

    private static let conversationQuery = """
    query PatchlightConversation($owner: String!, $name: String!, $number: Int!, $cursor: String) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          headRefOid
          reviewThreads(first: 100, after: $cursor) {
            nodes {
              id path line diffSide isOutdated isResolved viewerCanResolve
              comments(first: 100) {
                nodes { id databaseId body createdAt author { login } }
              }
            }
            pageInfo { hasNextPage endCursor }
          }
          commits(last: 1) {
            nodes {
              commit {
                statusCheckRollup {
                  contexts(first: 100) {
                    nodes {
                      __typename
                      ... on CheckRun { name status conclusion detailsUrl }
                      ... on StatusContext { context state targetUrl }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    """

    private static let resolveThreadMutation = """
    mutation PatchlightResolveThread($threadID: ID!) {
      resolveReviewThread(input: {threadId: $threadID}) { thread { id isResolved } }
    }
    """

    private static let unresolveThreadMutation = """
    mutation PatchlightUnresolveThread($threadID: ID!) {
      unresolveReviewThread(input: {threadId: $threadID}) { thread { id isResolved } }
    }
    """
}

extension DiffSide {
    fileprivate var apiCode: String {
        switch self {
            case .base: "LEFT"
            case .head: "RIGHT"
        }
    }
}

private struct EmptyBody: Encodable {}

private struct CommentBody: Encodable {
    let body: String
}

private struct FileCommentBody: Encodable {
    let body: String
    let commitID: String
    let path: String
    let subjectType: String

    enum CodingKeys: String, CodingKey {
        case body
        case commitID = "commit_id"
        case path
        case subjectType = "subject_type"
    }
}

private struct ReviewSubmissionBody: Encodable {
    let commitID: String
    let body: String?
    let event: String
    let comments: [ReviewCommentBody]

    enum CodingKeys: String, CodingKey {
        case commitID = "commit_id"
        case body
        case event
        case comments
    }
}

private struct ReviewCommentBody: Encodable {
    let path: String
    let body: String
    let line: Int?
    let side: String?
    let startLine: Int?
    let startSide: String?
    let subjectType: String?

    enum CodingKeys: String, CodingKey {
        case path
        case body
        case line
        case side
        case startLine = "start_line"
        case startSide = "start_side"
        case subjectType = "subject_type"
    }
}

private struct GraphQLRequestBody<Variables: Encodable & Sendable>: Encodable {
    let query: String
    let variables: Variables
}

private struct ConversationVariables: Encodable {
    let owner: String
    let name: String
    let number: Int
    let cursor: String?
}

private struct ThreadMutationVariables: Encodable {
    let threadID: String

    enum CodingKeys: String, CodingKey {
        case threadID
    }
}

private struct GraphQLResponseWire<Payload: Decodable>: Decodable {
    let data: Payload?
    let errors: [GraphQLErrorWire]?
}

private struct GraphQLMutationResponse: Decodable {
    let errors: [GraphQLErrorWire]?
}

private struct GraphQLErrorWire: Decodable {
    let message: String
}

private struct ConversationDataWire: Decodable {
    let repository: ConversationRepositoryWire
}

private struct ConversationRepositoryWire: Decodable {
    let pullRequest: ConversationPullRequestWire?
}

private struct ConversationPullRequestWire: Decodable {
    let headRefOID: String
    let reviewThreads: ConnectionWire<ReviewThreadWire>
    let commits: ConnectionWire<CommitNodeWire>

    enum CodingKeys: String, CodingKey {
        case headRefOID = "headRefOid"
        case reviewThreads
        case commits
    }
}

private struct ConnectionWire<Node: Decodable>: Decodable {
    let nodes: [Node]
    let pageInfo: PageInfoWire?
}

private struct PageInfoWire: Decodable {
    let hasNextPage: Bool
    let endCursor: String?
}

private struct ReviewThreadWire: Decodable {
    let id: String
    let path: String
    let line: Int?
    let diffSide: String?
    let isOutdated: Bool
    let isResolved: Bool
    let viewerCanResolve: Bool
    let comments: CommentConnectionWire

    var domainValue: ReviewThread {
        let side: DiffSide? = switch diffSide {
            case "LEFT": .base
            case "RIGHT": .head
            default: nil
        }
        return ReviewThread(
            id: GitHubNodeID(rawValue: id),
            path: path,
            line: line,
            side: side,
            isOutdated: isOutdated,
            isResolved: isResolved,
            canResolve: viewerCanResolve,
            comments: comments.nodes.map { $0.domainValue(kind: .reply) },
        )
    }
}

private struct CommentConnectionWire: Decodable {
    let nodes: [ThreadCommentWire]
}

private struct ThreadCommentWire: Decodable {
    let id: String
    let databaseID: Int64?
    let body: String
    let createdAt: Date
    let author: AuthorWire?

    enum CodingKeys: String, CodingKey {
        case id
        case databaseID = "databaseId"
        case body
        case createdAt
        case author
    }

    func domainValue(kind: ConversationCommentKind) -> ConversationComment {
        ConversationComment(
            id: GitHubNodeID(rawValue: id),
            databaseID: databaseID.map(GitHubCommentID.init(rawValue:)),
            authorLogin: author?.login ?? "[deleted]",
            bodyMarkdown: body,
            createdAt: createdAt,
            kind: kind,
        )
    }
}

private struct IssueCommentWire: Decodable {
    let id: Int64
    let nodeID: String
    let user: AuthorWire?
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case nodeID = "node_id"
        case user
        case body
        case createdAt = "created_at"
    }

    var domainValue: ConversationComment {
        ConversationComment(
            id: GitHubNodeID(rawValue: nodeID),
            databaseID: GitHubCommentID(rawValue: id),
            authorLogin: user?.login ?? "[deleted]",
            bodyMarkdown: body,
            createdAt: createdAt,
            kind: .issue,
        )
    }
}

private struct ReviewWire: Decodable {
    let nodeID: String
    let user: AuthorWire?
    let body: String?
    let state: String
    let submittedAt: Date?

    enum CodingKeys: String, CodingKey {
        case nodeID = "node_id"
        case user
        case body
        case state
        case submittedAt = "submitted_at"
    }

    var domainValue: PullRequestReview {
        get throws {
            let reviewState: PullRequestReviewState = switch state {
                case "APPROVED": .approved
                case "CHANGES_REQUESTED": .changesRequested
                case "COMMENTED": .commented
                case "DISMISSED": .dismissed
                case "PENDING": .pending
                default: throw GitHubAPIError.invalidResponse
            }
            return PullRequestReview(
                id: GitHubNodeID(rawValue: nodeID),
                authorLogin: user?.login ?? "[deleted]",
                bodyMarkdown: body ?? "",
                state: reviewState,
                submittedAt: submittedAt,
            )
        }
    }
}

private struct AuthorWire: Decodable {
    let login: String
}

private struct CommitNodeWire: Decodable {
    let commit: CommitWire
}

private struct CommitWire: Decodable {
    let statusCheckRollup: StatusCheckRollupWire?
}

private struct StatusCheckRollupWire: Decodable {
    let contexts: CheckContextsWire
}

private struct CheckContextsWire: Decodable {
    let nodes: [CheckContextWire]
}

private struct CheckContextWire: Decodable {
    let typeName: String
    let name: String?
    let context: String?
    let status: String?
    let conclusion: String?
    let state: String?
    let detailsURL: URL?
    let targetURL: URL?

    enum CodingKeys: String, CodingKey {
        case typeName = "__typename"
        case name
        case context
        case status
        case conclusion
        case state
        case detailsURL = "detailsUrl"
        case targetURL = "targetUrl"
    }

    var domainValue: CheckSummary? {
        let displayName = name ?? context
        guard let displayName, !displayName.isEmpty else { return nil }
        return CheckSummary(
            name: displayName,
            state: checkState,
            detailsURL: detailsURL ?? targetURL,
        )
    }

    private var checkState: CheckState {
        if typeName == "CheckRun", status != "COMPLETED" { return .pending }
        return switch conclusion ?? state {
            case "SUCCESS": .success
            case "FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED": .failure
            case "NEUTRAL": .neutral
            case "SKIPPED", "STALE": .skipped
            default: .pending
        }
    }
}

private struct NodeReceiptWire: Decodable {
    let nodeID: String?

    enum CodingKeys: String, CodingKey {
        case nodeID = "node_id"
    }
}

private struct APIErrorWire: Decodable {
    let message: String
}
