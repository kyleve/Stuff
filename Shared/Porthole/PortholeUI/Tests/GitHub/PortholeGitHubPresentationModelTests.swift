import Foundation
import PortholeGitHub
@testable import PortholeUI
import Testing

@MainActor
struct PortholeGitHubPresentationModelTests {
    @Test func branchRefreshRequiresAnEmptyWorkspaceAndPreservesUnsavedText() async throws {
        let repository = PortholeGitHubUIControlledRepository()
        let store = try GitHubWorkspaceStore(storageURL: nil)
        let model = try model(
            store: store,
            publisher: PortholeGitHubUIPublisher(),
            repository: repository,
        )
        await model.loadRepository()
        let original = try #require(model.snapshot).workspace.repositoryBase
        model.editorPath = "Sources/Example.swift"; model.openFile()
        await model.refreshRepositoryBase()
        #expect(await repository.branchReads == 2)
        #expect(model.editorText == "let value = 1\n")
        #expect(model.editor != nil)
        let advanced = try GitHubRepositorySnapshot(
            repository: original.repository,
            branch: original.branch,
            commit: GitHubObjectID(String(repeating: "d", count: 40)),
            tree: GitHubObjectID(String(repeating: "e", count: 40)),
            knownPaths: original.knownPaths,
            files: [.init(
                path: GitHubRepositoryPath("Sources/Example.swift"),
                text: "let value = 4\n",
                mode: .regular,
            )],
        )
        await repository.setBranchSnapshot(advanced)
        model.editorText = "let value = 2\n"
        #expect(!model.canRefreshRepositoryBase)
        await model.refreshRepositoryBase()
        #expect(await repository.branchReads == 2)
        #expect(model.editorText == "let value = 2\n")
        await model.saveFile()
        #expect(!model.canRefreshRepositoryBase)
        await model.refreshRepositoryBase()
        #expect(await repository.branchReads == 2)
        #expect(try #require(model.snapshot).workspace.patch.first?.after?
            .text == "let value = 2\n")
        await model.discardChanges()
        #expect(model.canRefreshRepositoryBase)
        await model.refreshRepositoryBase()
        #expect(await repository.branchReads == 3)
        let refreshed = try #require(model.snapshot)
        #expect(refreshed.workspace.repositoryBase.commit == advanced.commit)
        #expect(refreshed.workspace.patch.isEmpty)
        #expect(model.editor == nil)
        guard case .unreviewed = refreshed.review, case .idle = model.ciState else {
            Issue.record("A different base must start without a saved review or CI"); return
        }
    }

    @Test func editingAValidatedProposalClearsCIWhileSameBaseRefreshPreservesIt() async throws {
        let repository = PortholeGitHubUIControlledRepository()
        let store = try GitHubWorkspaceStore(storageURL: nil)
        let model = try model(
            store: store,
            publisher: PortholeGitHubUIPublisher(),
            repository: repository,
        )
        await model.loadRepository()
        model.editorPath = "Sources/Example.swift"; model.openFile(); model.editorText = "let value = 2\n"
        await model.saveFile(); model.title = "First fix"; await model.prepareReview()
        guard case let .prepared(proposal) = try #require(model.snapshot).review else {
            Issue.record("Expected prepared proposal"); return
        }
        await model.publish(proposal)
        guard case let .loaded(initial) = model.ciState else { Issue.record("Expected CI"); return }
        #expect(initial.state == .passed)
        #expect(!model.canRefreshRepositoryBase)
        await model.refreshRepositoryBase()
        #expect(await repository.branchReads == 1)
        await model.loadRepository()
        #expect(await repository.fixedBaseReads == 1)
        guard case let .loaded(retained) = model.ciState
        else { Issue.record("Same reviewed commit lost CI"); return }
        #expect(retained.commit == initial.commit)
        model.openFile(); model.editorText = "let value = 3\n"; await model.saveFile()
        await model.prepareReview()
        guard case let .prepared(next) = try #require(model.snapshot).review else {
            Issue.record("Expected replacement proposal"); return
        }
        #expect(next.proposalID != proposal.proposalID)
        guard case .idle = model.ciState
        else { Issue.record("An unpublished patch inherited passing CI"); return }
    }

    @Test(.timeLimit(
        .minutes(1),
    )) func lateCIReadsCannotValidateAnAgentReplacementProposal() async throws {
        let repository = PortholeGitHubUIControlledRepository()
        let store = try GitHubWorkspaceStore(storageURL: nil)
        let model = try model(
            store: store,
            publisher: PortholeGitHubUIPublisher(),
            repository: repository,
        )
        await model.loadRepository()
        model.editorPath = "Sources/Example.swift"; model.openFile(); model.editorText = "let value = 2\n"
        await model.saveFile(); model.title = "First fix"; await model.prepareReview()
        guard case let .prepared(proposal) = try #require(model.snapshot).review else {
            Issue.record("Expected prepared proposal"); return
        }
        await repository.suspendNextCI()
        let publication = Task { await model.publish(proposal) }
        await repository.waitForCI()
        do {
            let current = try await store.snapshot()
            let edited = try await store.setText(
                "let value = 3\n",
                at: GitHubRepositoryPath("Sources/Example.swift"),
                mode: .regular,
                expectedRevision: current.revision,
            )
            _ = try await store.prepare(
                title: "Second fix",
                body: "Synthetic test",
                evidence: .synthetic,
                author: PortholeGitHubUITestSupport.account,
                at: Date(timeIntervalSince1970: 100),
                expectedRevision: edited.revision,
            )
        } catch {
            await repository.completeCI()
            await publication.value
            throw error
        }
        await repository.completeCI()
        await publication.value
        guard case let .prepared(next) = try #require(model.snapshot).review else {
            Issue.record("Expected the current saved proposal"); return
        }
        #expect(next.proposalID != proposal.proposalID)
        guard case .idle = model.ciState
        else { Issue.record("Old CI callback validated the replacement proposal"); return }
    }

    @Test(.timeLimit(
        .minutes(1),
    )) func completingCIDoesNotUnlockASuspendedSourceLoad() async throws {
        let repository = PortholeGitHubUIControlledRepository()
        let store = try GitHubWorkspaceStore(storageURL: nil)
        let model = try model(
            store: store,
            publisher: PortholeGitHubUIPublisher(),
            repository: repository,
        )
        await model.loadRepository()
        model.editorPath = "Sources/Example.swift"; model.openFile(); model.editorText = "let value = 2\n"
        await model.saveFile(); model.title = "First fix"; await model.prepareReview()
        guard case let .prepared(proposal) = try #require(model.snapshot).review else {
            Issue.record("Expected prepared proposal"); return
        }
        await model.publish(proposal)
        guard case let .published(_, result) = try #require(model.snapshot).review else {
            Issue.record("Expected published proposal"); return
        }
        await repository.suspendNextCI()
        let ci = Task { await model.refreshCI(proposal: proposal, result: result) }
        await repository.waitForCI()
        await repository.suspendNextLoad()
        let source = Task { await model.loadRepository() }
        await repository.waitForLoad()
        await repository.completeCI()
        await ci.value
        #expect(model.isBusy)
        #expect(!model.canEditWorkspace)
        if case .loading = model.workspaceState {} else {
            Issue.record("CI completion replaced the source-load state")
        }
        await model.loadRepository()
        #expect(await repository.fixedBaseReads == 1)
        await repository.completeLoad()
        await source.value
        #expect(!model.isBusy)
        guard case let .loaded(status) = model.ciState else {
            Issue.record("The unchanged published review lost CI"); return
        }
        #expect(status.commit == result.commit)
    }

    @Test func personalEvidenceConsentAppliesOnlyToTheExactSavedProposal() async throws {
        let publisher = PortholeGitHubUIPublisher()
        let store = try GitHubWorkspaceStore(storageURL: nil)
        let model = try model(store: store, publisher: publisher)
        #expect(model.reviewEvidence == .synthetic)
        await model.loadRepository()
        model.editorPath = "Sources/Example.swift"; model.openFile(); model.editorText = "let value = 2\n"
        await model.saveFile()
        model.reviewEvidence = .personal; model.title = "Regression fixture"
        await model.prepareReview()
        guard case let .prepared(proposal) = try #require(model.snapshot).review
        else { Issue.record("Expected review"); return }
        await model.publish(proposal)
        #expect(await publisher.proposals.isEmpty)
        #expect(try await !store.snapshot().isPublishing)
        model.allowPersonalEvidence(true, for: proposal)
        await model.publish(proposal)
        #expect(await publisher.proposals.count == 1)
        model.openFile(); model.editorText = "let value = 3\n"; await model.saveFile()
        await model.prepareReview()
        guard case let .prepared(next) = try #require(model.snapshot).review
        else { Issue.record("Expected next review"); return }
        #expect(!model.personalEvidenceAllowed(for: next))
        await model.publish(next)
        #expect(await publisher.proposals.count == 1)
    }

    @Test func failedPublicationStartCannotUnlockAnotherInFlightProposal() async throws {
        let publisher = PortholeGitHubUIPublisher()
        let store = try GitHubWorkspaceStore(storageURL: nil)
        let model = try model(store: store, publisher: publisher)
        await model.loadRepository()
        model.editorPath = "Sources/Example.swift"; model.openFile(); model.editorText = "let value = 2\n"
        await model.saveFile(); model.title = "Fix value"; await model.prepareReview()
        guard case let .prepared(proposal) = try #require(model.snapshot).review
        else { Issue.record("Expected review"); return }
        _ = try await store.beginPublication(
            proposalID: proposal.proposalID,
            fingerprint: proposal.fingerprint,
        )
        await model.refreshWorkspace()
        #expect(!model.canRefreshRepositoryBase)
        await model.refreshRepositoryBase()
        await model.publish(proposal)
        #expect(await publisher.proposals.isEmpty)
        #expect(try await store.snapshot().isPublishing)
        try await store.publicationFailed(
            proposalID: proposal.proposalID,
            fingerprint: proposal.fingerprint,
        )
    }

    @Test(.timeLimit(
        .minutes(1),
    )) func cancellingSignInKeepsItsTaskUntilNativeCancellationFinishes() async throws {
        let authentication = PortholeGitHubUIControlledAuthentication()
        let model = try PortholeGitHubPresentationModel(
            authentication: authentication,
            repository: PortholeGitHubUIRepository(),
            publisher: PortholeGitHubUIPublisher(),
            workspaceStore: GitHubWorkspaceStore(storageURL: nil),
            installedSource: PortholeGitHubUITestSupport.installed(),
            initialRepository: GitHubRepository(owner: "fixture", name: "Example"),
            initialBranch: "main",
            initialPaths: [],
        )
        model.startSignIn()
        await authentication.waitForBegin()
        let cancel = Task { await model.cancelSignIn() }
        await authentication.waitForCancellation()
        model.startSignIn()
        #expect(await authentication.beginCount == 1)
        guard case .cancelling = model.authenticationState else {
            Issue.record("Expected cancellation to remain visible"); return
        }
        await authentication.completeCancellation()
        await cancel.value
        guard case .signedOut = model.authenticationState else {
            Issue.record("Expected sign-out after cancellation"); return
        }
        model.startSignIn()
        await authentication.waitForBegin()
        #expect(await authentication.beginCount == 2)
        let secondCancel = Task { await model.cancelSignIn() }
        await authentication.waitForCancellation()
        await authentication.completeCancellation()
        await secondCancel.value
    }

    @Test func preparesReviewWithoutPublicationAndRetriesSameProposalAfterUncertainReply(
    ) async throws {
        let publisher = PortholeGitHubUIPublisher()
        let store = try GitHubWorkspaceStore(storageURL: nil)
        let model = try model(store: store, publisher: publisher)
        await model.loadRepository()
        model.editorPath = "Sources/Example.swift"
        model.openFile()
        #expect(model.editorText == "let value = 1\n")
        model.editorText = "let value = 2\n"
        await model.saveFile()
        model.title = "Fix value"
        model.pullRequestBody = "Correct the observed result."
        await model.prepareReview()
        let snapshot = try #require(model.snapshot)
        guard case let .prepared(proposal) = snapshot.review
        else { Issue.record("Expected prepared review"); return }
        #expect(await publisher.proposals.isEmpty)
        #expect(proposal.installedSourceIsDirty)
        #expect(proposal.changes.first?.before?.text == "let value = 1\n")
        await publisher.loseReply()
        await model.publish(proposal)
        guard case .failed = model.publicationState
        else { Issue.record("Expected uncertain publication"); return }
        #expect(model.requiresPublicationReconciliation)
        #expect(!model.canEditWorkspace)
        #expect(!model.canRefreshRepositoryBase)
        await model.refreshRepositoryBase()
        await model.prepareReview()
        guard case let .publicationUncertain(saved) = try #require(model.snapshot).review else {
            Issue.record("An uncertain publication must remain the saved review"); return
        }
        #expect(saved.proposalID == proposal.proposalID)
        await model.publish(proposal)
        let attempts = await publisher.proposals
        #expect(attempts.count == 2)
        #expect(attempts[0].proposalID == attempts[1].proposalID)
        #expect(try attempts[0].fingerprint == attempts[1].fingerprint)
        guard case let .loaded(status) = model.ciState
        else { Issue.record("Expected CI status"); return }
        #expect(status.state == .pending)
    }

    @Test func concurrentAgentEditPreventsPublishingAStaleReview() async throws {
        let publisher = PortholeGitHubUIPublisher()
        let store = try GitHubWorkspaceStore(storageURL: nil)
        let model = try model(store: store, publisher: publisher)
        await model.loadRepository()
        model.editorPath = "Sources/Example.swift"; model.openFile(); model.editorText = "let value = 2\n"
        await model.saveFile()
        model.title = "Fix value"
        await model.prepareReview()
        let snapshot = try #require(model.snapshot)
        guard case let .prepared(proposal) = snapshot.review
        else { Issue.record("Expected review"); return }
        _ = try await store.setText(
            "let value = 3\n",
            at: GitHubRepositoryPath("Sources/Example.swift"),
            mode: .regular,
            expectedRevision: snapshot.revision,
        )
        await model.publish(proposal)
        #expect(await publisher.proposals.isEmpty)
        guard case .failed = model.publicationState
        else { Issue.record("A stale review must fail"); return }
    }

    private func model(
        store: GitHubWorkspaceStore,
        publisher: PortholeGitHubUIPublisher,
        repository: any GitHubRepositoryReading = PortholeGitHubUIRepository(),
    ) throws -> PortholeGitHubPresentationModel {
        try PortholeGitHubPresentationModel(
            authentication: PortholeGitHubUIAuthentication(),
            repository: repository,
            publisher: publisher,
            workspaceStore: store,
            installedSource: PortholeGitHubUITestSupport.installed(),
            initialRepository: GitHubRepository(owner: "fixture", name: "Example"),
            initialBranch: "main",
            initialPaths: [GitHubRepositoryPath("Sources/Example.swift")],
        )
    }
}
