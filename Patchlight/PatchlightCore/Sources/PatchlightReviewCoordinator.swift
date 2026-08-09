import Foundation

public struct ConversationRead: Sendable {
    public let value: PullRequestConversation
    public let source: CachedReadSource
    public let refreshedAt: Date
    public let fallbackReason: ReadFallbackReason?

    public init(
        value: PullRequestConversation,
        source: CachedReadSource,
        refreshedAt: Date,
        fallbackReason: ReadFallbackReason?,
    ) {
        self.value = value
        self.source = source
        self.refreshedAt = refreshedAt
        self.fallbackReason = fallbackReason
    }
}

public enum ReviewSubmissionOutcome: Sendable {
    case submitted(ReviewWriteReceipt, reconciledAfterUncertainResponse: Bool)
    case staleHead(PullRequestWorkspace, [DraftAnchorMapper.Result])
    case uncertain(requestID: String?)
}

public enum ImmediateWriteOutcome: Sendable {
    case submitted(ReviewWriteReceipt, reconciledAfterUncertainResponse: Bool)
    case uncertain(requestID: String?)
}

/// Coordinates encrypted drafts, fresh-head checks, one-shot writes, and
/// post-timeout reconciliation for one account world.
public actor PatchlightReviewCoordinator {
    private let github: any GitHubReading
    private let discussion: any GitHubReviewReading
    private let writer: any GitHubReviewWriting
    private let store: PatchlightAccountStore
    private let now: @Sendable () -> Date

    public init(
        github: any GitHubReading,
        discussion: any GitHubReviewReading,
        writer: any GitHubReviewWriting,
        store: PatchlightAccountStore,
    ) {
        self.github = github
        self.discussion = discussion
        self.writer = writer
        self.store = store
        now = Date.init
    }

    #if DEBUG
        @_spi(Testing)
        public init(
            github: any GitHubReading,
            discussion: any GitHubReviewReading,
            writer: any GitHubReviewWriting,
            store: PatchlightAccountStore,
            now: @escaping @Sendable () -> Date,
        ) {
            self.github = github
            self.discussion = discussion
            self.writer = writer
            self.store = store
            self.now = now
        }
    #endif

    public func conversation(
        for pullRequest: PullRequestRoute,
    ) async throws -> ConversationRead {
        do {
            let conversation = try await discussion.conversation(for: pullRequest)
            let refreshedAt = now()
            try await store.saveConversation(conversation, refreshedAt: refreshedAt)
            return ConversationRead(
                value: conversation,
                source: .live,
                refreshedAt: refreshedAt,
                fallbackReason: nil,
            )
        } catch {
            guard let cached = try await store.conversation(for: pullRequest.id) else {
                throw error
            }
            return ConversationRead(
                value: cached.value,
                source: .cache,
                refreshedAt: cached.refreshedAt,
                fallbackReason: Self.fallbackReason(for: error),
            )
        }
    }

    public func drafts(for pullRequest: PullRequestID) async throws -> [ReviewDraft] {
        try await store.drafts(for: pullRequest)
    }

    public func saveDraft(_ draft: ReviewDraft) async throws {
        try await store.saveDraft(draft)
    }

    public func removeDraft(_ id: UUID) async throws {
        try await store.removeDraft(id)
    }

    public func applyUniqueRemappings(_ results: [DraftAnchorMapper.Result]) async throws {
        for result in results {
            guard case let .remapped(draft) = result.resolution else { continue }
            try await store.saveDraft(draft)
        }
    }

    public func submit(
        workspace: PullRequestWorkspace,
        event: ReviewEvent,
        summary: String?,
        viewerLogin: String,
    ) async throws -> ReviewSubmissionOutcome {
        let drafts = try await store.drafts(for: workspace.summary.id)
        let freshWorkspace = try await github.workspace(for: workspace.summary.id)
        guard freshWorkspace.summary.headOID == workspace.summary.headOID else {
            return .staleHead(
                freshWorkspace,
                DraftAnchorMapper.map(
                    drafts,
                    from: workspace.summary.headOID,
                    to: freshWorkspace,
                ),
            )
        }

        let submission = ReviewSubmission(
            pullRequest: PullRequestRoute(summary: freshWorkspace.summary),
            headOID: freshWorkspace.summary.headOID,
            event: event,
            summary: summary,
            drafts: drafts,
        )
        let startedAt = now()
        do {
            let receipt = try await writer.submit(submission)
            try await remove(drafts)
            return .submitted(receipt, reconciledAfterUncertainResponse: false)
        } catch let error as GitHubReviewWriteError {
            guard case let .submissionStatusUncertain(requestID) = error else { throw error }
            if try await reviewExists(
                submission,
                viewerLogin: viewerLogin,
                submittedAfter: startedAt,
            ) {
                try await remove(drafts)
                return .submitted(
                    ReviewWriteReceipt(nodeID: nil, requestID: requestID),
                    reconciledAfterUncertainResponse: true,
                )
            }
            return .uncertain(requestID: requestID)
        }
    }

    public func postConversationComment(
        _ body: String,
        in pullRequest: PullRequestRoute,
        viewerLogin: String,
    ) async throws -> ImmediateWriteOutcome {
        try await immediateWrite(
            body: body,
            pullRequest: pullRequest,
            viewerLogin: viewerLogin,
            operation: { try await self.writer.postConversationComment(body, in: pullRequest) },
        )
    }

    public func postFileComment(
        _ body: String,
        path: String,
        headOID: GitObjectID,
        in pullRequest: PullRequestRoute,
        viewerLogin: String,
    ) async throws -> ImmediateWriteOutcome {
        try await immediateWrite(
            body: body,
            pullRequest: pullRequest,
            viewerLogin: viewerLogin,
            operation: {
                try await self.writer.postFileComment(
                    body,
                    path: path,
                    headOID: headOID,
                    in: pullRequest,
                )
            },
        )
    }

    public func reply(
        to commentID: GitHubCommentID,
        body: String,
        in pullRequest: PullRequestRoute,
        viewerLogin: String,
    ) async throws -> ImmediateWriteOutcome {
        try await immediateWrite(
            body: body,
            pullRequest: pullRequest,
            viewerLogin: viewerLogin,
            operation: {
                try await self.writer.reply(
                    to: commentID,
                    body: body,
                    in: pullRequest,
                )
            },
        )
    }

    public func setThread(_ threadID: GitHubNodeID, resolved: Bool) async throws {
        try await writer.setThread(threadID, resolved: resolved)
    }

    public func markFile(
        _ path: String,
        at depth: ReviewDepth,
        headOID: GitObjectID,
        in pullRequest: PullRequestRoute,
    ) async throws {
        try await writer.markFile(path, viewed: true, in: pullRequest)
        try await store.saveViewedDepth(ViewedFileDepth(
            pullRequest: pullRequest.id,
            path: path,
            headOID: headOID,
            depth: depth,
        ))
    }

    public func viewedDepths(for pullRequest: PullRequestID) async throws -> [ViewedFileDepth] {
        try await store.viewedDepths(for: pullRequest)
    }

    private func immediateWrite(
        body: String,
        pullRequest: PullRequestRoute,
        viewerLogin: String,
        operation: @Sendable () async throws -> ReviewWriteReceipt,
    ) async throws -> ImmediateWriteOutcome {
        let startedAt = now()
        do {
            return try await .submitted(operation(), reconciledAfterUncertainResponse: false)
        } catch let error as GitHubReviewWriteError {
            guard case let .submissionStatusUncertain(requestID) = error else { throw error }
            let refreshed = try await discussion.conversation(for: pullRequest)
            let comments = refreshed.issueComments + refreshed.threads.flatMap(\.comments)
            let exists = comments.contains {
                $0.authorLogin == viewerLogin && $0.bodyMarkdown == body && $0
                    .createdAt >= startedAt
            }
            return exists
                ? .submitted(
                    ReviewWriteReceipt(nodeID: nil, requestID: requestID),
                    reconciledAfterUncertainResponse: true,
                )
                : .uncertain(requestID: requestID)
        }
    }

    private func reviewExists(
        _ submission: ReviewSubmission,
        viewerLogin: String,
        submittedAfter: Date,
    ) async throws -> Bool {
        let refreshed = try await discussion.conversation(for: submission.pullRequest)
        let matchingReview = refreshed.reviews.contains { review in
            review.authorLogin == viewerLogin &&
                review.bodyMarkdown == (submission.summary ?? "") &&
                (review.submittedAt ?? .distantPast) >= submittedAfter
        }
        let commentBodies = refreshed.threads.flatMap(\.comments).filter {
            $0.authorLogin == viewerLogin && $0.createdAt >= submittedAfter
        }.map(\.bodyMarkdown)
        return matchingReview && submission.drafts.allSatisfy { commentBodies.contains($0.body) }
    }

    private func remove(_ drafts: [ReviewDraft]) async throws {
        for draft in drafts {
            try await store.removeDraft(draft.id)
        }
    }

    private static func fallbackReason(for error: any Error) -> ReadFallbackReason {
        if let urlError = error as? URLError,
           [
               .notConnectedToInternet,
               .networkConnectionLost,
               .cannotConnectToHost,
               .cannotFindHost,
               .timedOut,
           ].contains(urlError.code)
        {
            return ReadFallbackReason(code: .offline, message: error.localizedDescription)
        }
        if error as? GitHubAuthenticationError == .reauthorizationRequired ||
            error as? GitHubAPIError == .authenticationExpired
        {
            return ReadFallbackReason(
                code: .reauthorizationRequired,
                message: error.localizedDescription,
            )
        }
        if case .rateLimited = error as? GitHubAPIError {
            return ReadFallbackReason(code: .rateLimited, message: error.localizedDescription)
        }
        return ReadFallbackReason(code: .refreshFailed, message: error.localizedDescription)
    }
}
