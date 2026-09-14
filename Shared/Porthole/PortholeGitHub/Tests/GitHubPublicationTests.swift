import Foundation
import PortholeGitHub
import Testing

struct GitHubPublicationTests {
    @Test func reconcilesLostBranchAndPullResponsesWithoutDuplicates() async throws {
        let remote = GitHubScriptedPublishingRemote(behavior: .init(
            loseBranchResponse: true,
            losePullResponse: true,
        ))
        let publisher = GitHubPublisher(remote: remote)
        let proposal = try GitHubTestFixtures.proposal()
        let first = try await publisher.publish(proposal)
        let second = try await publisher.publish(proposal)
        #expect(first == second)
        #expect(await remote.counts.branches == 1)
        #expect(await remote.counts.pullRequests == 1)
    }

    @Test func uncertainPullRequestResumesWithSameProposalAfterReload() async throws {
        let remote = GitHubScriptedPublishingRemote(behavior: .init(
            losePullResponse: true,
            hidePullAfterLostResponse: true,
        ))
        let proposal = try GitHubTestFixtures.proposal()
        let publisher = GitHubPublisher(remote: remote)
        await #expect(throws: GitHubError.publicationUncertain(.pullRequest)) {
            try await publisher.publish(proposal)
        }
        let reloaded = try JSONDecoder().decode(
            GitHubPullRequestProposal.self,
            from: JSONEncoder().encode(proposal),
        )
        let resumed = try await GitHubPublisher(remote: remote).publish(reloaded)
        #expect(resumed.number == 12)
        #expect(try proposal.fingerprint == reloaded.fingerprint)
        #expect(await remote.counts.pullRequests == 1)
    }

    @Test func refusesBranchCollisionWithoutForcePush() async throws {
        let remote = GitHubScriptedPublishingRemote(behavior: .init(conflictingBranch: true))
        let publisher = GitHubPublisher(remote: remote)
        let proposal = try GitHubTestFixtures.proposal()
        await #expect(throws: GitHubError.branchConflict) { try await publisher.publish(proposal) }
        #expect(await remote.counts.branches == 0)
        #expect(await remote.counts.pullRequests == 0)
    }

    @Test func rejectsUnrelatedPullAfterUncertainResponse() async throws {
        let remote = GitHubScriptedPublishingRemote(behavior: .init(
            losePullResponse: true,
            mismatchedPull: true,
        ))
        let publisher = GitHubPublisher(remote: remote)
        let proposal = try GitHubTestFixtures.proposal()
        await #expect(throws: GitHubError.pullRequestConflict) {
            try await publisher.publish(proposal)
        }
    }

    @Test func reviewRemainsImmutableAfterWorkspaceChanges() throws {
        var workspace = try GitHubTestFixtures.workspace()
        let path = try GitHubRepositoryPath("Sources/Example.swift")
        try workspace.setText("approved\n", at: path, mode: .regular)
        let proposal = try GitHubPullRequestProposal(
            proposalID: UUID(),
            workspace: workspace,
            title: "Fix",
            body: "",
            evidence: .synthetic,
            author: GitHubTestFixtures.account,
            createdAt: GitHubTestFixtures.now,
        )
        let reviewed = try proposal.fingerprint
        try workspace.setText("later unapproved edit\n", at: path, mode: .regular)
        #expect(try proposal.fingerprint == reviewed)
        #expect(try proposal.diff.contains("+approved\n"))
        #expect(try proposal.diff.contains("later unapproved edit") == false)
    }
}
