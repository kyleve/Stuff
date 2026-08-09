import Foundation
@_spi(Testing) import PatchlightCore
import Testing

struct PatchlightReviewCoordinatorTests {
    @Test func staleHeadFreezesAndDoesNotWrite() async throws {
        let setup = try PatchlightCoreTestSupport.makeScope(name: #function)
        let old = workspace(head: PatchlightCoreTestSupport.objectID("a"))
        let fresh = workspace(head: PatchlightCoreTestSupport.objectID("b"))
        let services = ScriptedReviewServices(
            workspaceResult: .success(fresh),
            conversationResult: .success(conversation(for: fresh)),
            submissionResult: .success(ReviewWriteReceipt(nodeID: nil, requestID: nil)),
        )
        let coordinator = PatchlightReviewCoordinator(
            github: services,
            discussion: services,
            writer: services,
            store: setup.scope.accountStore,
            now: { Date(timeIntervalSince1970: 100) },
        )
        try await coordinator.saveDraft(draft(for: old))

        let outcome = try await coordinator.submit(
            workspace: old,
            event: .comment,
            summary: "Review",
            viewerLogin: "reviewer",
        )

        guard case .staleHead = outcome else {
            Issue.record("Expected submission to freeze on a new head")
            return
        }
        #expect(await services.submissionCount == 0)
        #expect(try await coordinator.drafts(for: old.summary.id).count == 1)
    }

    @Test func ambiguousResponseReconcilesByReadingAndNeverRetries() async throws {
        let setup = try PatchlightCoreTestSupport.makeScope(name: #function)
        let workspace = workspace(head: PatchlightCoreTestSupport.objectID("a"))
        let draft = draft(for: workspace)
        let reconciled = conversation(
            for: workspace,
            reviewBody: "Summary",
            commentBody: draft.body,
        )
        let services = ScriptedReviewServices(
            workspaceResult: .success(workspace),
            conversationResult: .success(reconciled),
            submissionResult: .failure(
                GitHubReviewWriteError.submissionStatusUncertain(requestID: "request-7"),
            ),
        )
        let coordinator = PatchlightReviewCoordinator(
            github: services,
            discussion: services,
            writer: services,
            store: setup.scope.accountStore,
            now: { Date(timeIntervalSince1970: 100) },
        )
        try await coordinator.saveDraft(draft)

        let outcome = try await coordinator.submit(
            workspace: workspace,
            event: .comment,
            summary: "Summary",
            viewerLogin: "reviewer",
        )

        guard case let .submitted(_, reconciledAfterUncertainResponse) = outcome else {
            Issue.record("Expected read reconciliation to prove the write")
            return
        }
        #expect(reconciledAfterUncertainResponse)
        #expect(await services.submissionCount == 1)
        #expect(await services.conversationCount == 1)
        #expect(try await coordinator.drafts(for: workspace.summary.id).isEmpty)
    }

    @Test func offlineFreshHeadCheckNeverQueuesAWrite() async throws {
        let setup = try PatchlightCoreTestSupport.makeScope(name: #function)
        let workspace = workspace(head: PatchlightCoreTestSupport.objectID("a"))
        let services = ScriptedReviewServices(
            workspaceResult: .failure(URLError(.notConnectedToInternet)),
            conversationResult: .success(conversation(for: workspace)),
            submissionResult: .success(ReviewWriteReceipt(nodeID: nil, requestID: nil)),
        )
        let coordinator = PatchlightReviewCoordinator(
            github: services,
            discussion: services,
            writer: services,
            store: setup.scope.accountStore,
        )

        await #expect(throws: URLError.self) {
            try await coordinator.submit(
                workspace: workspace,
                event: .approve,
                summary: nil,
                viewerLogin: "reviewer",
            )
        }
        #expect(await services.submissionCount == 0)
    }

    private func draft(for workspace: PullRequestWorkspace) -> ReviewDraft {
        let lines = workspace.files[0].hunks[0].lines
        return ReviewDraft(
            id: UUID(),
            pullRequest: workspace.summary.id,
            anchor: DiffAnchor(
                path: workspace.files[0].path,
                side: .head,
                commitOID: workspace.summary.headOID,
                blobOID: workspace.files[0].headBlobOID,
                line: 1,
                startLine: nil,
                contextFingerprint: DraftAnchorMapper.fingerprint(lineIndex: 0, in: lines),
            ),
            body: "Please check this line",
            updatedAt: Date(timeIntervalSince1970: 50),
        )
    }

    private func workspace(head: GitObjectID) -> PullRequestWorkspace {
        let line = DiffLine(
            id: .init(rawValue: "line"),
            kind: .addition,
            oldLine: nil,
            newLine: 1,
            text: "let safe = true",
        )
        return PullRequestWorkspace(
            summary: PullRequestSummary(
                id: PatchlightCoreTestSupport.pullRequestID,
                repository: RepositoryCoordinates(owner: "acme", name: "widget"),
                title: "Review",
                authorLogin: "author",
                isDraft: false,
                headOID: head,
                updatedAt: Date(timeIntervalSince1970: 1),
                reviewRequestSource: .direct,
            ),
            bodyMarkdown: nil,
            baseOID: PatchlightCoreTestSupport.objectID("f"),
            files: [DiffFile(
                path: "Sources/App.swift",
                previousPath: nil,
                status: .modified,
                additions: 1,
                deletions: 0,
                baseBlobOID: PatchlightCoreTestSupport.objectID("c"),
                headBlobOID: PatchlightCoreTestSupport.objectID("d"),
                availability: .complete,
                hunks: [DiffHunk(
                    id: .init(rawValue: "hunk"),
                    header: "@@",
                    oldStart: 1,
                    oldCount: 0,
                    newStart: 1,
                    newCount: 1,
                    lines: [line],
                )],
            )],
            isFileListComplete: true,
        )
    }

    private func conversation(
        for workspace: PullRequestWorkspace,
        reviewBody: String = "",
        commentBody: String? = nil,
    ) -> PullRequestConversation {
        let date = Date(timeIntervalSince1970: 100)
        let comments = commentBody.map {
            [ConversationComment(
                id: GitHubNodeID(rawValue: "comment"),
                databaseID: GitHubCommentID(rawValue: 1),
                authorLogin: "reviewer",
                bodyMarkdown: $0,
                createdAt: date,
                kind: .reply,
            )]
        } ?? []
        return PullRequestConversation(
            pullRequest: PullRequestRoute(summary: workspace.summary),
            headOID: workspace.summary.headOID,
            issueComments: [],
            reviews: [PullRequestReview(
                id: GitHubNodeID(rawValue: "review"),
                authorLogin: "reviewer",
                bodyMarkdown: reviewBody,
                state: .commented,
                submittedAt: date,
            )],
            threads: comments.isEmpty ? [] : [ReviewThread(
                id: GitHubNodeID(rawValue: "thread"),
                path: "Sources/App.swift",
                line: 1,
                side: .head,
                isOutdated: false,
                isResolved: false,
                canResolve: true,
                comments: comments,
            )],
            checks: [],
        )
    }
}

private actor ScriptedReviewServices: GitHubReading, GitHubReviewReading, GitHubReviewWriting {
    let workspaceResult: Result<PullRequestWorkspace, any Error>
    let conversationResult: Result<PullRequestConversation, any Error>
    let submissionResult: Result<ReviewWriteReceipt, any Error>
    private(set) var submissionCount = 0
    private(set) var conversationCount = 0

    init(
        workspaceResult: Result<PullRequestWorkspace, any Error>,
        conversationResult: Result<PullRequestConversation, any Error>,
        submissionResult: Result<ReviewWriteReceipt, any Error>,
    ) {
        self.workspaceResult = workspaceResult
        self.conversationResult = conversationResult
        self.submissionResult = submissionResult
    }

    func workspace(for _: PullRequestID) throws -> PullRequestWorkspace {
        try workspaceResult.get()
    }

    func conversation(for _: PullRequestRoute) throws -> PullRequestConversation {
        conversationCount += 1
        return try conversationResult.get()
    }

    func submit(_: ReviewSubmission) throws -> ReviewWriteReceipt {
        submissionCount += 1
        return try submissionResult.get()
    }

    func viewer() throws -> GitHubViewer {
        throw TestFailure.unused
    }

    func dashboard() throws -> ReviewDashboard {
        throw TestFailure.unused
    }

    func installations() throws -> [GitHubInstallationSummary] {
        throw TestFailure.unused
    }

    func repositories() throws -> [RepositorySummary] {
        throw TestFailure.unused
    }

    func reviewRequests() throws -> [PullRequestSummary] {
        throw TestFailure.unused
    }

    func ownPullRequests() throws -> [PullRequestSummary] {
        throw TestFailure.unused
    }

    func pullRequests(in _: RepositoryID) throws -> [PullRequestSummary] {
        throw TestFailure.unused
    }

    func blob(repository _: RepositoryID, oid _: GitObjectID, path _: String) throws -> Data {
        throw TestFailure.unused
    }

    func postConversationComment(_: String, in _: PullRequestRoute) throws -> ReviewWriteReceipt {
        throw TestFailure.unused
    }

    func postFileComment(
        _: String,
        path _: String,
        headOID _: GitObjectID,
        in _: PullRequestRoute,
    ) throws -> ReviewWriteReceipt {
        throw TestFailure.unused
    }

    func reply(
        to _: GitHubCommentID,
        body _: String,
        in _: PullRequestRoute,
    ) throws -> ReviewWriteReceipt {
        throw TestFailure.unused
    }

    func setThread(_: GitHubNodeID, resolved _: Bool) throws {
        throw TestFailure.unused
    }

    func markFile(_: String, viewed _: Bool, in _: PullRequestRoute) throws {
        throw TestFailure.unused
    }

    private enum TestFailure: Error {
        case unused
    }
}
