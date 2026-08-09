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

    @Test func correctionsAreHeadScopedAndRepositoryOverridesRoundTripEncrypted() async throws {
        let setup = try PatchlightCoreTestSupport.makeScope(name: #function)
        let pullRequest = PatchlightCoreTestSupport.pullRequestID
        let currentHead = PatchlightCoreTestSupport.objectID("c")
        let correction = ReviewCorrection(
            id: UUID(),
            pullRequest: pullRequest,
            headOID: currentHead,
            path: "Sources/Generated.swift",
            hunkID: DiffHunk.ID(rawValue: "hunk-1"),
            kind: .mechanical,
        )
        let settings = PatchlightRepositorySettings(
            repository: pullRequest.repository,
            aiEnabled: true,
            imageAIEnabled: false,
            overrides: PatchlightLocalRepositoryOverrides(
                review: PatchlightReviewRules(
                    alwaysReview: ["Sources/Auth/**"],
                    generated: ["Generated/**"],
                    mechanical: [],
                    tests: ["**/Tests/**"],
                ),
                snapshots: PatchlightSnapshotRules(
                    include: ["VisualTests/**/*.png"],
                    exclude: ["VisualTests/Fixtures/**"],
                ),
                manualSnapshotPaths: ["Assets/Golden.png"],
            ),
        )

        try await setup.scope.accountStore.saveCorrection(correction)
        try await setup.scope.accountStore.saveRepositorySettings(settings)

        #expect(try await setup.scope.accountStore.corrections(
            for: pullRequest,
            headOID: currentHead,
        ) == [correction])
        #expect(try await setup.scope.accountStore.corrections(
            for: pullRequest,
            headOID: PatchlightCoreTestSupport.objectID("d"),
        ).isEmpty)
        #expect(try await setup.scope.accountStore.repositorySettings(
            for: pullRequest.repository,
        ) == settings)

        try await setup.scope.accountStore.removeCorrections(
            for: pullRequest,
            headOID: currentHead,
            path: correction.path,
            hunkID: correction.hunkID,
        )
        #expect(try await setup.scope.accountStore.corrections(
            for: pullRequest,
            headOID: currentHead,
        ).isEmpty)
    }

    @Test func providerAnalysisRoundTripsEncryptedAndMarksCacheHits() async throws {
        let setup = try PatchlightCoreTestSupport.makeScope(name: #function)
        let run = ReviewAnalysisRun(
            provider: .openAI,
            preset: .balanced,
            modelID: "gpt-5.6-terra",
            headOID: PatchlightCoreTestSupport.objectID(),
            analysis: ReviewAnalysis(
                hunks: [],
                files: [],
                summary: "Nothing risky found.",
                usage: .zero,
            ),
            createdAt: Date(timeIntervalSince1970: 100),
            isCacheHit: false,
        )

        try await setup.scope.accountStore.saveAnalysis(run, cacheKey: "cache-key")
        let cached = try #require(await setup.scope.accountStore.analysis(
            cacheKey: "cache-key",
        ))

        #expect(cached.provider == run.provider)
        #expect(cached.modelID == run.modelID)
        #expect(cached.headOID == run.headOID)
        #expect(cached.analysis == run.analysis)
        #expect(cached.isCacheHit)
    }
}
