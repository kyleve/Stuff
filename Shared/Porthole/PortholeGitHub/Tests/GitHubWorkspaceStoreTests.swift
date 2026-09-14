import Foundation
@testable import PortholeGitHub
import Testing

struct GitHubWorkspaceStoreTests {
    @Test(arguments: [false, true])
    func unchangedSavePreservesTheExactPreparedOrPublishedReview(published: Bool) async throws {
        let fixture = try await GitHubPreparedWorkspaceTestFixture(storageURL: nil)
        let result = try GitHubPublishedPullRequest(
            number: 12,
            url: #require(URL(string: "https://github.com/sample-user/Example/pull/12")),
            commit: GitHubTestFixtures.publishedCommit,
        )
        if published {
            _ = try await fixture.store.beginPublication(
                proposalID: fixture.proposal.proposalID,
                fingerprint: fixture.proposal.fingerprint,
            )
            _ = try await fixture.store.finishPublication(
                result,
                proposalID: fixture.proposal.proposalID,
                fingerprint: fixture.proposal.fingerprint,
            )
        }
        let before = try await fixture.store.snapshot()
        let path = try GitHubRepositoryPath("Sources/Example.swift")
        let unchanged = try await fixture.store.setText(
            "let value = 2\n",
            at: path,
            mode: .regular,
            expectedRevision: before.revision,
        )
        #expect(unchanged.revision == before.revision)
        #expect(unchanged.workspace.patch == before.workspace.patch)
        switch unchanged.review {
            case let .prepared(proposal):
                #expect(!published)
                #expect(try proposal.fingerprint == fixture.proposal.fingerprint)
            case let .published(proposal, savedResult):
                #expect(published)
                #expect(try proposal.fingerprint == fixture.proposal.fingerprint)
                #expect(savedResult == result)
            case .unreviewed, .publicationUncertain:
                Issue.record("An unchanged save must preserve the exact review")
        }
        await #expect(throws: GitHubError.branchConflict) {
            try await fixture.store.setText(
                "let value = 2\n",
                at: path,
                mode: .regular,
                expectedRevision: UUID(),
            )
        }
        _ = try await fixture.store.beginPublication(
            proposalID: fixture.proposal.proposalID,
            fingerprint: fixture.proposal.fingerprint,
        )
        try await fixture.store.publicationFailed(
            proposalID: fixture.proposal.proposalID,
            fingerprint: fixture.proposal.fingerprint,
        )
        let locked = try await fixture.store.snapshot()
        await #expect(throws: GitHubError.publicationReconciliationRequired) {
            try await fixture.store.setText(
                "let value = 2\n",
                at: path,
                mode: .regular,
                expectedRevision: locked.revision,
            )
        }
        #expect(try await fixture.store.snapshot().revision == locked.revision)
    }

    @Test func repeatedRemovalAndEmptyDiscardPreserveTheirRevision() async throws {
        let fixture = try await GitHubPreparedWorkspaceTestFixture(storageURL: nil)
        let path = try GitHubRepositoryPath("Sources/Example.swift")
        let removed = try await fixture.store.remove(
            at: path,
            expectedRevision: fixture.snapshot.revision,
        )
        let reviewed = try await fixture.store.prepare(
            title: "Remove unused source",
            body: "Synthetic removal fixture",
            evidence: .synthetic,
            author: GitHubTestFixtures.account,
            at: GitHubTestFixtures.now,
            expectedRevision: removed.revision,
        )
        let unchanged = try await fixture.store.remove(
            at: path,
            expectedRevision: reviewed.revision,
        )
        #expect(unchanged.revision == reviewed.revision)
        guard case let .prepared(originalProposal) = reviewed.review,
              case let .prepared(savedProposal) = unchanged.review
        else {
            Issue.record("Removing an already removed file must preserve its review")
            return
        }
        #expect(try savedProposal.fingerprint == originalProposal.fingerprint)
        let discarded = try await fixture.store.discardChanges(expectedRevision: unchanged.revision)
        #expect(discarded.workspace.patch.isEmpty)
        let empty = try await fixture.store.discardChanges(expectedRevision: discarded.revision)
        #expect(empty.revision == discarded.revision)
        await #expect(throws: GitHubError.branchConflict) {
            try await fixture.store.discardChanges(expectedRevision: unchanged.revision)
        }
    }

    @Test(arguments: [false, true])
    func unresolvedPublicationLocksAllWorkspaceChanges(relaunch: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
        }
        let url = directory.appending(path: "workspace.json")
        let fixture = try await GitHubPreparedWorkspaceTestFixture(storageURL: url)
        _ = try await fixture.store.beginPublication(
            proposalID: fixture.proposal.proposalID,
            fingerprint: fixture.proposal.fingerprint,
        )
        let store: GitHubWorkspaceStore
        if relaunch {
            store = try GitHubWorkspaceStore(storageURL: url)
        } else {
            try await fixture.store.publicationFailed(
                proposalID: fixture.proposal.proposalID,
                fingerprint: fixture.proposal.fingerprint,
            )
            store = fixture.store
        }
        let locked = try await store.snapshot()
        #expect(!locked.isPublishing)
        guard case let .publicationUncertain(saved) = locked.review else {
            Issue.record("Expected the saved publication to require reconciliation")
            return
        }
        #expect(try saved.fingerprint == fixture.proposal.fingerprint)
        let path = try GitHubRepositoryPath("Sources/Example.swift")
        await #expect(throws: GitHubError.publicationReconciliationRequired) {
            try await store.setText(
                "new proposal",
                at: path,
                mode: .regular,
                expectedRevision: locked.revision,
            )
        }
        await #expect(throws: GitHubError.publicationReconciliationRequired) {
            try await store.remove(at: path, expectedRevision: locked.revision)
        }
        await #expect(throws: GitHubError.publicationReconciliationRequired) {
            try await store.discardChanges(expectedRevision: locked.revision)
        }
        await #expect(throws: GitHubError.publicationReconciliationRequired) {
            try await store.prepare(
                title: "Replacement proposal",
                body: "Must not replace the uncertain publication",
                evidence: .synthetic,
                author: GitHubTestFixtures.account,
                at: GitHubTestFixtures.now,
                expectedRevision: locked.revision,
            )
        }
        await #expect(throws: GitHubError.publicationReconciliationRequired) {
            try await store.load(
                base: locked.workspace.repositoryBase,
                installedSource: locked.workspace.installedSource,
            )
        }
        await #expect(throws: GitHubError.branchConflict) {
            try await store.beginPublication(proposalID: UUID(), fingerprint: saved.fingerprint)
        }
        await #expect(throws: GitHubError.branchConflict) {
            try await store.beginPublication(proposalID: saved.proposalID, fingerprint: "changed")
        }
        #expect(try await store.snapshot().revision == locked.revision)
        let wire = try #require(JSONSerialization
            .jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(wire["version"] as? Int == 1)
        #expect((wire["review"] as? [String: Any])?["publicationUncertain"] != nil)
    }

    @Test func uncertainPublicationReconcilesOneBranchAndPullRequestAfterRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
        }
        let url = directory.appending(path: "workspace.json")
        let fixture = try await GitHubPreparedWorkspaceTestFixture(storageURL: url)
        let proposal = try await fixture.store.beginPublication(
            proposalID: fixture.proposal.proposalID,
            fingerprint: fixture.proposal.fingerprint,
        )
        let remote = GitHubScriptedPublishingRemote(behavior: .init(
            losePullResponse: true,
            hidePullAfterLostResponse: true,
        ))
        let publisher = GitHubPublisher(remote: remote)
        await #expect(throws: GitHubError.publicationUncertain(.pullRequest)) {
            try await publisher.publish(proposal)
        }
        try await fixture.store.publicationFailed(
            proposalID: proposal.proposalID,
            fingerprint: proposal.fingerprint,
        )
        let restored = try GitHubWorkspaceStore(storageURL: url)
        let retry = try await restored.beginPublication(
            proposalID: proposal.proposalID,
            fingerprint: proposal.fingerprint,
        )
        #expect(retry.branch == proposal.branch)
        #expect(try retry.fingerprint == proposal.fingerprint)
        let published = try await publisher.publish(retry)
        _ = try await restored.finishPublication(
            published,
            proposalID: retry.proposalID,
            fingerprint: retry.fingerprint,
        )
        let finalStore = try GitHubWorkspaceStore(storageURL: url)
        let reconciled = try await finalStore.snapshot()
        guard case let .published(saved, savedResult) = reconciled.review else {
            Issue.record("Expected reconciled publication to survive relaunch")
            return
        }
        #expect(try saved.fingerprint == proposal.fingerprint)
        #expect(savedResult == published)
        #expect(await remote.counts.branches == 1)
        #expect(await remote.counts.pullRequests == 1)
        let editable = try await finalStore.discardChanges(expectedRevision: reconciled.revision)
        #expect(editable.workspace.patch.isEmpty)
    }

    @Test func publicationCannotBeginUntilItsUncertainStateIsSaved() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
        }
        let url = directory.appending(path: "workspace.json")
        let fixture = try await GitHubPreparedWorkspaceTestFixture(storageURL: url)
        let savedPrepared = try Data(contentsOf: url)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        await #expect(throws: (any Error).self) {
            try await fixture.store.beginPublication(
                proposalID: fixture.proposal.proposalID,
                fingerprint: fixture.proposal.fingerprint,
            )
        }
        let unchanged = try await fixture.store.snapshot()
        #expect(!unchanged.isPublishing)
        #expect(unchanged.revision == fixture.snapshot.revision)
        guard case let .prepared(proposal) = unchanged.review else {
            Issue.record("A failed save must not begin publication")
            return
        }
        #expect(try proposal.fingerprint == fixture.proposal.fingerprint)
        try FileManager.default.removeItem(at: url)
        try savedPrepared.write(to: url, options: .atomic)
        let restored = try GitHubWorkspaceStore(storageURL: url)
        guard case .prepared = try await restored.snapshot().review else {
            Issue.record("The existing v1 prepared review must remain readable")
            return
        }
    }

    @Test func loadingAnotherFileAtTheSameCommitPreservesExistingEdits() async throws {
        let fixture = try GitHubTestFixtures.workspace()
        let firstPath = try GitHubRepositoryPath("Sources/Example.swift")
        let secondPath = try GitHubRepositoryPath("Sources/Other.swift")
        let base = try GitHubRepositorySnapshot(
            repository: fixture.repositoryBase.repository,
            branch: fixture.repositoryBase.branch,
            commit: fixture.repositoryBase.commit,
            tree: fixture.repositoryBase.tree,
            knownPaths: [firstPath, secondPath],
            files: fixture.repositoryBase.files,
        )
        let store = try GitHubWorkspaceStore(storageURL: nil)
        let loaded = try await store.load(base: base, installedSource: fixture.installedSource)
        _ = try await store.setText(
            "let value = 2\n",
            at: firstPath,
            mode: .regular,
            expectedRevision: loaded.revision,
        )
        let additional = try GitHubRepositorySnapshot(
            repository: base.repository,
            branch: base.branch,
            commit: base.commit,
            tree: base.tree,
            knownPaths: base.knownPaths,
            files: [.init(path: secondPath, text: "let other = 1\n", mode: .regular)],
        )
        let expanded = try await store.load(
            base: additional,
            installedSource: fixture.installedSource,
        )
        #expect(expanded.workspace.repositoryBase.files.count == 2)
        #expect(expanded.workspace.file(at: firstPath)?.text == "let value = 2\n")
        #expect(expanded.workspace.file(at: secondPath)?.text == "let other = 1\n")
        #expect(expanded.workspace.patch.count == 1)
    }

    @Test func exactRevisionProtectsConcurrentEditsAndInvalidatesPriorReview() async throws {
        let fixture = try GitHubTestFixtures.workspace(isDirty: true)
        let store = try GitHubWorkspaceStore(storageURL: nil)
        let first = try await store.load(
            base: fixture.repositoryBase,
            installedSource: fixture.installedSource,
        )
        #expect(first.workspace.patch.isEmpty)
        let path = try GitHubRepositoryPath("Sources/Example.swift")
        let edited = try await store.setText(
            "let value = 2\n",
            at: path,
            mode: .regular,
            expectedRevision: first.revision,
        )
        await #expect(throws: GitHubError.branchConflict) {
            try await store.setText(
                "overwrite",
                at: path,
                mode: .regular,
                expectedRevision: first.revision,
            )
        }
        let reviewed = try await store.prepare(
            title: "Fix value",
            body: "Explain fix",
            evidence: .synthetic,
            author: GitHubTestFixtures.account,
            at: GitHubTestFixtures.now,
            expectedRevision: edited.revision,
        )
        guard case .prepared = reviewed.review
        else { Issue.record("Expected saved review"); return }
        let newer = try await store.setText(
            "let value = 3\n",
            at: path,
            mode: .regular,
            expectedRevision: reviewed.revision,
        )
        guard case .unreviewed = newer.review
        else { Issue.record("An edit must invalidate old review"); return }
        #expect(newer.workspace.installedSource.files.first?.text == "let value = 99\n")
        #expect(newer.workspace.patch.first?.before?.text == "let value = 1\n")
    }

    @Test func persistsExactProposalBeforePublicationAndRestoresAfterUncertainReply() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
        }
        let url = directory.appending(path: "workspace.json")
        let fixture = try GitHubTestFixtures.workspace()
        let store = try GitHubWorkspaceStore(storageURL: url)
        let first = try await store.load(
            base: fixture.repositoryBase,
            installedSource: fixture.installedSource,
        )
        let edited = try await store.setText(
            "let value = 2\n",
            at: GitHubRepositoryPath("Sources/Example.swift"),
            mode: .regular,
            expectedRevision: first.revision,
        )
        let reviewed = try await store.prepare(
            title: "Fix value",
            body: "Explain fix",
            evidence: .synthetic,
            author: GitHubTestFixtures.account,
            at: GitHubTestFixtures.now,
            expectedRevision: edited.revision,
        )
        guard case let .prepared(proposal) = reviewed.review
        else { Issue.record("Expected review"); return }
        _ = try await store.beginPublication(
            proposalID: proposal.proposalID,
            fingerprint: proposal.fingerprint,
        )
        await #expect(throws: GitHubError.busy) {
            try await store.remove(
                at: GitHubRepositoryPath("Sources/Example.swift"),
                expectedRevision: reviewed.revision,
            )
        }
        let restored = try GitHubWorkspaceStore(storageURL: url)
        let retried = try await restored.beginPublication(
            proposalID: proposal.proposalID,
            fingerprint: proposal.fingerprint,
        )
        #expect(try retried.fingerprint == proposal.fingerprint)
        #expect(retried.branch == proposal.branch)
        try await restored.publicationFailed(
            proposalID: proposal.proposalID,
            fingerprint: proposal.fingerprint,
        )
        let result = try GitHubPublishedPullRequest(
            number: 12,
            url: #require(URL(string: "https://github.com/sample-user/Example/pull/12")),
            commit: GitHubTestFixtures.publishedCommit,
        )
        _ = try await restored.beginPublication(
            proposalID: proposal.proposalID,
            fingerprint: proposal.fingerprint,
        )
        await #expect(throws: GitHubError.branchConflict) {
            try await restored.publicationFailed(
                proposalID: UUID(),
                fingerprint: proposal.fingerprint,
            )
        }
        await #expect(throws: GitHubError.branchConflict) {
            try await restored.finishPublication(
                result,
                proposalID: UUID(),
                fingerprint: proposal.fingerprint,
            )
        }
        #expect(try await restored.snapshot().isPublishing)
        let published = try await restored.finishPublication(
            result,
            proposalID: proposal.proposalID,
            fingerprint: proposal.fingerprint,
        )
        guard case let .published(saved, savedResult) = published.review
        else { Issue.record("Expected persisted publication"); return }
        #expect(saved.proposalID == proposal.proposalID)
        #expect(savedResult == result)
    }
}
