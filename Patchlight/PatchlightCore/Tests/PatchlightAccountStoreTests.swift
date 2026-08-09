import Foundation
import PatchlightCore
import Testing

struct PatchlightAccountStoreTests {
    @Test func draftsRoundTripThroughEncryptedPersistence() async throws {
        let setup = try PatchlightCoreTestSupport.makeScope(name: #function)
        let draft = ReviewDraft(
            id: UUID(),
            pullRequest: PatchlightCoreTestSupport.pullRequestID,
            anchor: DiffAnchor(
                path: "Sources/Auth.swift",
                side: .head,
                commitOID: PatchlightCoreTestSupport.objectID(),
                blobOID: PatchlightCoreTestSupport.objectID("b"),
                line: 42,
                startLine: nil,
                contextFingerprint: "fingerprint",
            ),
            body: "Could this race during token rotation?",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )

        try await setup.scope.accountStore.saveDraft(draft)
        #expect(
            try await setup.scope.accountStore.drafts(for: draft.pullRequest) == [draft],
        )

        try await setup.scope.accountStore.removeDraft(draft.id)
        #expect(try await setup.scope.accountStore.drafts(for: draft.pullRequest).isEmpty)
    }

    @Test func conversationAndViewedDepthRoundTripEncryptedRecords() async throws {
        let setup = try PatchlightCoreTestSupport.makeScope(name: #function)
        let pullRequest = PatchlightCoreTestSupport.pullRequestID
        let route = PullRequestRoute(
            id: pullRequest,
            repository: RepositoryCoordinates(owner: "acme", name: "widget"),
        )
        let conversation = PullRequestConversation(
            pullRequest: route,
            headOID: PatchlightCoreTestSupport.objectID(),
            issueComments: [],
            reviews: [],
            threads: [],
            checks: [CheckSummary(name: "Tests", state: .success, detailsURL: nil)],
        )
        let refreshedAt = Date(timeIntervalSince1970: 100)
        let viewed = ViewedFileDepth(
            pullRequest: pullRequest,
            path: "Sources/App.swift",
            headOID: conversation.headOID,
            depth: .balanced,
        )

        try await setup.scope.accountStore.saveConversation(
            conversation,
            refreshedAt: refreshedAt,
        )
        try await setup.scope.accountStore.saveViewedDepth(viewed)

        #expect(try await setup.scope.accountStore.conversation(for: pullRequest)?
            .value == conversation)
        #expect(try await setup.scope.accountStore.conversation(for: pullRequest)?
            .refreshedAt == refreshedAt)
        #expect(try await setup.scope.accountStore.viewedDepths(for: pullRequest) == [viewed])
    }
}
