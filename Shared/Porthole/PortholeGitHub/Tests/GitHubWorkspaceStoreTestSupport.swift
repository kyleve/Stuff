import Foundation
import PortholeGitHub

struct GitHubPreparedWorkspaceTestFixture {
    let store: GitHubWorkspaceStore
    let snapshot: GitHubWorkspaceSnapshot
    let proposal: GitHubPullRequestProposal

    init(storageURL: URL?) async throws {
        let workspace = try GitHubTestFixtures.workspace()
        store = try GitHubWorkspaceStore(storageURL: storageURL)
        let initial = try await store.load(
            base: workspace.repositoryBase,
            installedSource: workspace.installedSource,
        )
        let edited = try await store.setText(
            "let value = 2\n",
            at: GitHubRepositoryPath("Sources/Example.swift"),
            mode: .regular,
            expectedRevision: initial.revision,
        )
        snapshot = try await store.prepare(
            title: "Fix value",
            body: "Explain fix",
            evidence: .synthetic,
            author: GitHubTestFixtures.account,
            at: GitHubTestFixtures.now,
            expectedRevision: edited.revision,
        )
        guard case let .prepared(proposal) = snapshot.review else {
            throw GitHubError.invalidResponse
        }
        self.proposal = proposal
    }
}
