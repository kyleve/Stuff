import Foundation
@_spi(Testing) import PatchlightCore
@_spi(Testing) import StuffCore
import Testing

struct ReviewAnalysisCoordinatorTests {
    @Test func explicitRunCachesByHeadProviderPresetSchemaAndPolicy() async throws {
        let response = ProviderAnalysisTestSupport.response([
            "id": "resp-final",
            "output": [[
                "type": "message",
                "content": [[
                    "type": "output_text",
                    "text": ProviderAnalysisTestSupport.structuredReview(),
                ]],
            ]],
            "usage": ["input_tokens": 10, "output_tokens": 5],
        ])
        let transport = ScriptedHTTPTransport([.success(response)])
        let setup = try PatchlightCoreTestSupport.makeScope(name: #function)
        let credentials = ProviderCredentialManager(store: setup.credentials)
        try await credentials.set(ProviderAPIKey("secret"), for: .openAI)
        let workspace = workspace()
        let coordinator = ReviewAnalysisCoordinator(
            accountID: setup.scope.accountID,
            github: ProviderAnalysisTestSupport.github(),
            store: setup.scope.accountStore,
            credentials: credentials,
            transport: transport,
            now: { Date(timeIntervalSince1970: 100) },
        )
        let configuration = try configuration(imageEnabled: false)

        let first = try await coordinator.analyze(
            workspace: workspace,
            deterministicPlan: plan(workspace),
            configuration: configuration,
        )
        let second = try await coordinator.analyze(
            workspace: workspace,
            deterministicPlan: plan(workspace),
            configuration: configuration,
        )

        #expect(!first.isCacheHit)
        #expect(second.isCacheHit)
        #expect(first.analysis.hunks.count == 1)
        #expect(await transport.capturedRequests().count == 1)
    }

    @Test func selectedProviderFailureNeverFallsBackToTheOtherStoredProvider() async throws {
        let transport = ScriptedHTTPTransport([.success(PatchlightHTTPResponse(
            statusCode: 500,
            headers: [:],
            body: Data("{\"error\":{\"message\":\"unavailable\"}}".utf8),
        ))])
        let setup = try PatchlightCoreTestSupport.makeScope(name: #function)
        let credentials = ProviderCredentialManager(store: setup.credentials)
        try await credentials.set(ProviderAPIKey("openai"), for: .openAI)
        try await credentials.set(ProviderAPIKey("anthropic"), for: .anthropic)
        let workspace = workspace()
        let coordinator = ReviewAnalysisCoordinator(
            accountID: setup.scope.accountID,
            github: ProviderAnalysisTestSupport.github(),
            store: setup.scope.accountStore,
            credentials: credentials,
            transport: transport,
        )

        await #expect(throws: AIAnalysisError.self) {
            try await coordinator.analyze(
                workspace: workspace,
                deterministicPlan: plan(workspace),
                configuration: configuration(imageEnabled: false),
            )
        }
        let requests = await transport.capturedRequests()
        #expect(requests.count == 1)
        #expect(requests[0].url.host == "api.openai.com")
    }

    @Test func imageAnalysisRequiresSeparateConsentAndCachesExactBlobPair() async throws {
        let response = ProviderAnalysisTestSupport.response([
            "id": "resp-image",
            "output": [[
                "type": "message",
                "content": [[
                    "type": "output_text",
                    "text": "{\"summary\":\"Looks expected.\",\"findings\":[]}",
                ]],
            ]],
        ])
        let transport = ScriptedHTTPTransport([.success(response)])
        let setup = try PatchlightCoreTestSupport.makeScope(name: #function)
        let credentials = ProviderCredentialManager(store: setup.credentials)
        try await credentials.set(ProviderAPIKey("secret"), for: .openAI)
        let workspace = workspace()
        let coordinator = ReviewAnalysisCoordinator(
            accountID: setup.scope.accountID,
            github: ProviderAnalysisTestSupport.github(),
            store: setup.scope.accountStore,
            credentials: credentials,
            transport: transport,
        )
        let pair = SnapshotImagePair(
            file: workspace.files[0],
            base: SnapshotImageAsset(
                oid: PatchlightCoreTestSupport.objectID("c"),
                data: Data([1, 2, 3]),
            ),
            head: SnapshotImageAsset(
                oid: PatchlightCoreTestSupport.objectID("d"),
                data: Data([4, 5, 6]),
            ),
            comparison: nil,
        )

        await #expect(throws: AIAnalysisError.imageConsentRequired) {
            try await coordinator.analyzeImages(
                pair: pair,
                workspace: workspace,
                configuration: configuration(imageEnabled: false),
            )
        }
        let first = try await coordinator.analyzeImages(
            pair: pair,
            workspace: workspace,
            configuration: configuration(imageEnabled: true),
        )
        let second = try await coordinator.analyzeImages(
            pair: pair,
            workspace: workspace,
            configuration: configuration(imageEnabled: true),
        )

        #expect(!first.isCacheHit)
        #expect(second.isCacheHit)
        #expect(await transport.capturedRequests().count == 1)
    }

    private func configuration(imageEnabled: Bool) throws -> ReviewAnalysisConfiguration {
        try ReviewAnalysisConfiguration(
            globallyEnabled: true,
            repositoryEnabled: true,
            imageAnalysisEnabled: imageEnabled,
            selection: ProviderAnalysisTestSupport.selection(provider: .openAI),
            policyFingerprint: "policy-v1",
        )
    }

    private func workspace() -> PullRequestWorkspace {
        let request = ProviderAnalysisTestSupport.request()
        return PullRequestWorkspace(
            summary: PullRequestSummary(
                id: request.pullRequest,
                repository: RepositoryCoordinates(owner: "acme", name: "widget"),
                title: "Review",
                authorLogin: "author",
                isDraft: false,
                headOID: request.headOID,
                createdAt: .distantPast,
                updatedAt: .distantPast,
                reviewRequestSource: .direct,
                actionability: .directRequest,
            ),
            bodyMarkdown: nil,
            baseOID: request.baseOID,
            files: request.files,
            isFileListComplete: true,
            repositoryConfiguration: .absent,
        )
    }

    private func plan(_ workspace: PullRequestWorkspace) -> DeterministicReviewPlan {
        let file = workspace.files[0]
        let hunks = file.hunks.map { hunk in
            HunkReviewPlan(
                hunk: hunk,
                assessment: ReviewAssessment(
                    hunkID: hunk.id,
                    category: .unknown,
                    minimumDepth: .balanced,
                    confidence: 1,
                    evidence: [],
                    isPartial: false,
                ),
                isHardSafetySignal: false,
                hasIndependentMechanicalEvidence: false,
                aiAnalysis: nil,
            )
        }
        return DeterministicReviewPlan(
            files: [FileReviewPlan(
                file: file,
                minimumDepth: .balanced,
                hunks: hunks,
                isSnapshot: false,
            )],
            configurationWarning: nil,
        )
    }
}
