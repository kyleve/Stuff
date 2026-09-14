import Foundation

/// Native GitHub REST adapter. Requests receive credentials immediately before transmission.
public struct GitHubRepositoryClient: GitHubPublishingRemote, Sendable {
    private let clientID: GitHubClientID
    private let transport: any GitHubHTTPTransport
    private let credentials: any GitHubCredentialStore
    private let now: @Sendable () -> Date

    public init(
        clientID: GitHubClientID,
        transport: any GitHubHTTPTransport,
        credentials: any GitHubCredentialStore,
        now: @escaping @Sendable () -> Date,
    ) {
        self.clientID = clientID
        self.transport = transport
        self.credentials = credentials
        self.now = now
    }

    public func snapshot(
        repository: GitHubRepository,
        branch: String,
        paths: [GitHubRepositoryPath],
        maximumFileBytes: Int,
    ) async throws -> GitHubRepositorySnapshot {
        try repository.validate()
        try GitHubBranch.validate(branch)
        guard maximumFileBytes > 0 else { throw GitHubError.fileTooLarge }
        for path in paths {
            try path.validate()
        }
        struct Commit: Decodable {
            struct Details: Decodable { let tree: Object }
            let sha: String
            let commit: Details
        }
        let commit: Commit = try await get(path: repositoryPath(repository) + ["commits", branch])
        let commitID = try GitHubObjectID(commit.sha)
        let treeID = try GitHubObjectID(commit.commit.tree.sha)
        return try await snapshot(
            repository: repository,
            branch: branch,
            commit: commitID,
            tree: treeID,
            paths: paths,
            maximumFileBytes: maximumFileBytes,
        )
    }

    /// Loads selected files from the captured tree without resolving the branch again.
    public func snapshot(
        base: GitHubRepositorySnapshot,
        paths: [GitHubRepositoryPath],
        maximumFileBytes: Int,
    ) async throws -> GitHubRepositorySnapshot {
        try base.validate()
        guard maximumFileBytes > 0 else { throw GitHubError.fileTooLarge }
        for path in paths {
            try path.validate()
        }
        let selected = try await snapshot(
            repository: base.repository,
            branch: base.branch,
            commit: base.commit,
            tree: base.tree,
            paths: paths,
            maximumFileBytes: maximumFileBytes,
        )
        guard selected.knownPaths == base.knownPaths else { throw GitHubError.branchConflict }
        return selected
    }

    private func snapshot(
        repository: GitHubRepository,
        branch: String,
        commit commitID: GitHubObjectID,
        tree treeID: GitHubObjectID,
        paths: [GitHubRepositoryPath],
        maximumFileBytes: Int,
    ) async throws -> GitHubRepositorySnapshot {
        let tree: Tree = try await get(
            path: repositoryPath(repository) + ["git", "trees", treeID.rawValue],
            query: [URLQueryItem(name: "recursive", value: "1")],
        )
        guard !tree.truncated else { throw GitHubError.incompleteRepositoryTree }
        var indexed: [GitHubRepositoryPath: Tree.Entry] = [:]
        for entry in tree.tree {
            let path = try GitHubRepositoryPath(entry.path)
            guard indexed[path] == nil else { throw GitHubError.invalidResponse }
            indexed[path] = entry
        }
        var files: [GitHubSourceFile] = []
        for path in Set(paths).sorted() {
            guard let entry = indexed[path] else { throw GitHubError.missingBaseFile }
            guard entry.type == "blob",
                  let mode = GitHubTextFileMode(rawValue: entry.mode)
            else { throw GitHubError.unsupportedFile }
            guard (entry.size ?? Int.max) <= maximumFileBytes
            else { throw GitHubError.fileTooLarge }
            let blobID = try GitHubObjectID(entry.sha)
            let blob: Blob = try await get(path: repositoryPath(repository) + [
                "git",
                "blobs",
                blobID.rawValue,
            ])
            guard blob.encoding == "base64", let data = Data(
                base64Encoded: blob.content,
                options: .ignoreUnknownCharacters,
            ) else {
                throw GitHubError.invalidResponse
            }
            guard data.count <= maximumFileBytes else { throw GitHubError.fileTooLarge }
            guard let text = String(data: data, encoding: .utf8),
                  !text.contains("\0") else { throw GitHubError.unsupportedFile }
            files.append(GitHubSourceFile(path: path, text: text, mode: mode))
        }
        return try GitHubRepositorySnapshot(
            repository: repository,
            branch: branch,
            commit: commitID,
            tree: treeID,
            knownPaths: Set(indexed.keys),
            files: files,
        )
    }

    public func createCommit(for proposal: GitHubPullRequestProposal) async throws
        -> GitHubObjectID
    {
        try proposal.validate()
        guard try await account() == proposal.author else { throw GitHubError.accountChanged }
        let prefix = repositoryPath(proposal.base.repository)
        struct BaseCommit: Decodable { let tree: Object }
        let base: BaseCommit = try await get(path: prefix + [
            "git",
            "commits",
            proposal.base.commit.rawValue,
        ])
        guard base.tree.sha == proposal.base.tree.rawValue else { throw GitHubError.branchConflict }
        // Tree deletions require an explicit JSON null; ordinary optional Codable omits it.
        let entries: [[String: Any]] = proposal.changes.map { change in
            if let after = change.after {
                [
                    "path": change.path.rawValue,
                    "mode": after.mode.rawValue,
                    "type": "blob",
                    "content": after.text,
                ]
            } else {
                [
                    "path": change.path.rawValue,
                    "mode": change.before!.mode.rawValue,
                    "type": "blob",
                    "sha": NSNull(),
                ]
            }
        }
        let treeBody = try JSONSerialization.data(
            withJSONObject: ["base_tree": proposal.base.tree.rawValue, "tree": entries],
            options: .sortedKeys,
        )
        let treeResponse = try await request(
            method: "POST",
            path: prefix + ["git", "trees"],
            body: treeBody,
            query: [],
        )
        let tree: Object = try decode(treeResponse, allowed: [201])
        let treeID = try GitHubObjectID(tree.sha)
        struct Identity: Encodable { let name: String; let email: String; let date: String }
        struct CommitBody: Encodable {
            let message: String
            let tree: String
            let parents: [String]
            let author: Identity
            let committer: Identity
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let identity = Identity(
            name: proposal.author.login,
            email: "\(proposal.author.userID)+\(proposal.author.login)@users.noreply.github.com",
            date: formatter.string(from: proposal.createdAt),
        )
        let body = try CommitBody(
            message: proposal.title + "\n\n" + (proposal.marker),
            tree: treeID.rawValue,
            parents: [proposal.base.commit.rawValue],
            author: identity,
            committer: identity,
        )
        let response = try await request(
            method: "POST",
            path: prefix + ["git", "commits"],
            body: JSONEncoder().encode(body),
            query: [],
        )
        let created: Object = try decode(response, allowed: [201])
        return try GitHubObjectID(created.sha)
    }

    public func account() async throws -> GitHubAccount {
        guard let credential = try await credentials.credential(for: clientID)
        else { throw GitHubError.unauthenticated }
        if let expiresAt = credential.expiresAt,
           expiresAt <= now() { throw GitHubError.credentialExpired }
        return credential.account
    }

    public func branchHead(
        repository: GitHubRepository,
        branch: String,
    ) async throws -> GitHubObjectID? {
        try repository.validate()
        try GitHubBranch.validate(branch)
        let response = try await request(
            method: "GET",
            path: repositoryPath(repository) + ["git", "ref", "heads"] + branch
                .components(separatedBy: "/"),
            body: nil,
            query: [],
        )
        if response.statusCode == 404 { return nil }
        struct Reference: Decodable { let object: Object }
        let reference: Reference = try decode(response, allowed: [200])
        return try GitHubObjectID(reference.object.sha)
    }

    public func createBranch(
        repository: GitHubRepository,
        branch: String,
        commit: GitHubObjectID,
    ) async throws {
        try repository.validate()
        try GitHubBranch.validate(branch)
        try commit.validate()
        struct Body: Encodable { let ref: String; let sha: String }
        let response = try await request(
            method: "POST",
            path: repositoryPath(repository) + ["git", "refs"],
            body: JSONEncoder().encode(Body(ref: "refs/heads/" + branch, sha: commit.rawValue)),
            query: [],
        )
        guard response.statusCode == 201
        else { throw GitHubError.requestFailed(statusCode: response.statusCode) }
    }

    public func pullRequests(
        repository: GitHubRepository,
        branch: String,
    ) async throws -> [GitHubExistingPullRequest] {
        try repository.validate()
        try GitHubBranch.validate(branch)
        var results: [GitHubExistingPullRequest] = []
        var page = 1
        while true {
            try Task.checkCancellation()
            let response = try await request(
                method: "GET",
                path: repositoryPath(repository) + ["pulls"],
                body: nil,
                query: [
                    URLQueryItem(name: "state", value: "all"),
                    URLQueryItem(name: "head", value: repository.owner + ":" + branch),
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: String(page)),
                ],
            )
            let requests: [PullRequest] = try decode(response, allowed: [200])
            results += try requests.map { try $0.existing() }
            if requests.count < 100 { break }
            page += 1
        }
        return results
    }

    public func createDraftPullRequest(
        proposal: GitHubPullRequestProposal,
        commit: GitHubObjectID,
    ) async throws -> GitHubPublishedPullRequest {
        try proposal.validate()
        struct Body: Encodable {
            let title: String; let body: String; let head: String; let base: String; let draft: Bool
        }
        let body = try Body(
            title: proposal.title,
            body: proposal.body + "\n\n" + (proposal.marker),
            head: proposal.branch,
            base: proposal.base.branch,
            draft: true,
        )
        let response = try await request(
            method: "POST",
            path: repositoryPath(proposal.base.repository) + ["pulls"],
            body: JSONEncoder().encode(body),
            query: [],
        )
        let request: PullRequest = try decode(response, allowed: [201])
        let result = try request.existing()
        guard result.result.commit == commit,
              result.baseBranch == proposal.base.branch,
              result.isDraft,
              try result.body.contains(proposal.marker)
        else { throw GitHubError.pullRequestConflict }
        return result.result
    }

    func get<Response: Decodable>(
        path: [String],
        query: [URLQueryItem] = [],
    ) async throws -> Response {
        try await decode(
            request(method: "GET", path: path, body: nil, query: query),
            allowed: [200],
        )
    }

    func request(
        method: String,
        path: [String],
        body: Data?,
        query: [URLQueryItem],
    ) async throws -> GitHubHTTPResponse {
        guard let credential = try await credentials.credential(for: clientID)
        else { throw GitHubError.unauthenticated }
        if let expiresAt = credential.expiresAt,
           expiresAt <= now() { throw GitHubError.credentialExpired }
        if let expectedAccount = GitHubPublisher.Authorization.expectedAccount,
           credential.account != expectedAccount { throw GitHubError.accountChanged }
        let unreserved =
            CharacterSet(
                charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~",
            )
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.percentEncodedPath = "/" + path
            .map { $0.addingPercentEncoding(withAllowedCharacters: unreserved)! }
            .joined(separator: "/")
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw GitHubError.invalidIdentifier }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Porthole", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return try await transport.send(request)
    }

    func decode<Response: Decodable>(
        _ response: GitHubHTTPResponse,
        allowed: Set<Int>,
    ) throws -> Response {
        guard allowed.contains(response.statusCode)
        else { throw GitHubError.requestFailed(statusCode: response.statusCode) }
        return try JSONDecoder().decode(Response.self, from: response.body)
    }

    func repositoryPath(_ repository: GitHubRepository) -> [String] {
        [
            "repos",
            repository.owner,
            repository.name,
        ]
    }

    private struct Object: Decodable { let sha: String }
    private struct Blob: Decodable { let content: String; let encoding: String }
    private struct Tree: Decodable {
        struct Entry: Decodable {
            let path: String; let mode: String; let type: String; let sha: String; let size: Int?
        }

        let tree: [Entry]
        let truncated: Bool
    }

    private struct PullRequest: Decodable {
        struct Head: Decodable { let sha: String }
        struct Base: Decodable { let ref: String }
        let number: Int
        let html_url: URL
        let head: Head
        let base: Base
        let body: String?
        let draft: Bool

        func existing() throws -> GitHubExistingPullRequest {
            guard html_url.scheme == "https",
                  html_url.host == "github.com" else { throw GitHubError.invalidResponse }
            return try GitHubExistingPullRequest(
                result: GitHubPublishedPullRequest(
                    number: number,
                    url: html_url,
                    commit: GitHubObjectID(head.sha),
                ),
                body: body ?? "",
                baseBranch: base.ref,
                isDraft: draft,
            )
        }
    }
}
