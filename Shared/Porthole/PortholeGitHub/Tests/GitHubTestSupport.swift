import Foundation
@testable import PortholeGitHub

enum GitHubTestFixtures {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let account = GitHubAccount(userID: 123, login: "sample-user")
    static var clientID: GitHubClientID {
        get throws { try GitHubClientID("Iv1.test") }
    }

    static var repository: GitHubRepository {
        get throws { try GitHubRepository(
            owner: "sample-user",
            name: "Example",
        ) }
    }

    static var commit: GitHubObjectID {
        get throws { try GitHubObjectID(String(
            repeating: "a",
            count: 40,
        )) }
    }

    static var tree: GitHubObjectID {
        get throws { try GitHubObjectID(String(
            repeating: "b",
            count: 40,
        )) }
    }

    static var publishedCommit: GitHubObjectID {
        get throws { try GitHubObjectID(String(
            repeating: "c",
            count: 40,
        )) }
    }

    static func workspace(isDirty: Bool = false) throws -> GitHubSourceWorkspace {
        let path = try GitHubRepositoryPath("Sources/Example.swift")
        let baseFile = GitHubSourceFile(path: path, text: "let value = 1\n", mode: .regular)
        let installedFile = GitHubSourceFile(
            path: path,
            text: isDirty ? "let value = 99\n" : baseFile.text,
            mode: .regular,
        )
        return try GitHubSourceWorkspace(
            installedSource: GitHubInstalledSource(
                buildIdentity: "installed-build",
                isDirty: isDirty,
                files: [installedFile],
            ),
            repositoryBase: GitHubRepositorySnapshot(
                repository: repository,
                branch: "main",
                commit: commit,
                tree: tree,
                knownPaths: [path],
                files: [baseFile],
            ),
        )
    }

    static func proposal() throws -> GitHubPullRequestProposal {
        var workspace = try workspace()
        try workspace.setText(
            "let value = 2\n",
            at: GitHubRepositoryPath("Sources/Example.swift"),
            mode: .regular,
        )
        return try GitHubPullRequestProposal(
            proposalID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            workspace: workspace,
            title: "Correct example value",
            body: "Fix the observed result.",
            evidence: .synthetic,
            author: account,
            createdAt: now,
        )
    }
}

actor GitHubMemoryCredentialStore: GitHubCredentialStore {
    private var values: [GitHubClientID: GitHubCredential] = [:]

    func credential(for clientID: GitHubClientID) -> GitHubCredential? {
        values[clientID]
    }

    func save(_ credential: GitHubCredential, for clientID: GitHubClientID) {
        values[clientID] = credential
    }

    func remove(for clientID: GitHubClientID) {
        values[clientID] = nil
    }

    static func authenticated() async throws -> GitHubMemoryCredentialStore {
        let result = GitHubMemoryCredentialStore()
        try await result.save(
            GitHubCredential(
                account: GitHubTestFixtures.account,
                accessToken: "synthetic-test-token",
                expiresAt: nil,
            ),
            for: GitHubTestFixtures.clientID,
        )
        return result
    }
}

actor GitHubScriptedTransport: GitHubHTTPTransport {
    enum Step {
        case response(Int, String)
        case disconnected
    }

    enum Failure: Error { case disconnected; case exhausted }
    private var steps: [Step]
    private(set) var requests: [URLRequest] = []

    init(_ steps: [Step]) {
        self.steps = steps
    }

    func send(_ request: URLRequest) throws -> GitHubHTTPResponse {
        requests.append(request)
        guard !steps.isEmpty else { throw Failure.exhausted }
        switch steps.removeFirst() {
            case let .response(status, body): return GitHubHTTPResponse(
                    statusCode: status,
                    headers: [:],
                    body: Data(body.utf8),
                )
            case .disconnected: throw Failure.disconnected
        }
    }
}

actor GitHubScriptedPublishingRemote: GitHubPublishingRemote {
    struct Behavior {
        var loseBranchResponse = false
        var losePullResponse = false
        var hidePullAfterLostResponse = false
        var conflictingBranch = false
        var mismatchedPull = false
    }

    struct Counts {
        var branches = 0
        var pullRequests = 0
    }

    private let behavior: Behavior
    private var head: GitHubObjectID?
    private var existing: GitHubExistingPullRequest?
    private var hideNextPullRead = false
    private(set) var counts = Counts()

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func createCommit(for _: GitHubPullRequestProposal) throws -> GitHubObjectID {
        try GitHubTestFixtures.publishedCommit
    }

    func branchHead(repository _: GitHubRepository, branch _: String) throws -> GitHubObjectID? {
        if behavior.conflictingBranch { return try GitHubTestFixtures.commit }
        return head
    }

    func createBranch(
        repository _: GitHubRepository,
        branch _: String,
        commit: GitHubObjectID,
    ) throws {
        counts.branches += 1
        head = commit
        if behavior.loseBranchResponse { throw GitHubScriptedTransport.Failure.disconnected }
    }

    func pullRequests(
        repository _: GitHubRepository,
        branch _: String,
    ) -> [GitHubExistingPullRequest] {
        if hideNextPullRead {
            hideNextPullRead = false
            return []
        }
        return existing.map { [$0] } ?? []
    }

    func createDraftPullRequest(
        proposal: GitHubPullRequestProposal,
        commit: GitHubObjectID,
    ) throws -> GitHubPublishedPullRequest {
        counts.pullRequests += 1
        let result = GitHubPublishedPullRequest(
            number: 12,
            url: URL(string: "https://github.com/sample-user/Example/pull/12")!,
            commit: commit,
        )
        existing = try GitHubExistingPullRequest(
            result: result,
            body: behavior.mismatchedPull ? "different proposal" : proposal.marker,
            baseBranch: proposal.base.branch,
            isDraft: true,
        )
        if behavior.losePullResponse {
            hideNextPullRead = behavior.hidePullAfterLostResponse
            throw GitHubScriptedTransport.Failure.disconnected
        }
        return result
    }
}
