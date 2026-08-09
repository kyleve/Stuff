import CryptoKit
import Foundation

/// Owns one explicit BYOK run: cache lookup, risk-prioritized chunking,
/// provider selection, bounded tools, validation, and encrypted persistence.
public actor ReviewAnalysisCoordinator {
    private let accountID: PatchlightAccountID
    private let github: any GitHubReading
    private let store: PatchlightAccountStore
    private let credentials: ProviderCredentialManager
    private let transport: any PatchlightHTTPTransport
    private let now: @Sendable () -> Date

    public init(
        accountID: PatchlightAccountID,
        github: any GitHubReading,
        store: PatchlightAccountStore,
        credentials: ProviderCredentialManager,
        transport: any PatchlightHTTPTransport,
    ) {
        self.accountID = accountID
        self.github = github
        self.store = store
        self.credentials = credentials
        self.transport = transport
        now = { Date() }
    }

    #if DEBUG
        @_spi(Testing)
        public init(
            accountID: PatchlightAccountID,
            github: any GitHubReading,
            store: PatchlightAccountStore,
            credentials: ProviderCredentialManager,
            transport: any PatchlightHTTPTransport,
            now: @escaping @Sendable () -> Date,
        ) {
            self.accountID = accountID
            self.github = github
            self.store = store
            self.credentials = credentials
            self.transport = transport
            self.now = now
        }
    #endif

    public func analyze(
        workspace: PullRequestWorkspace,
        deterministicPlan: DeterministicReviewPlan,
        configuration: ReviewAnalysisConfiguration,
    ) async throws -> ReviewAnalysisRun {
        try Task.checkCancellation()
        guard configuration.globallyEnabled, configuration.repositoryEnabled else {
            throw AIAnalysisError.consentRequired
        }
        let cacheKey = try cacheKey(
            kind: .review,
            workspace: workspace,
            configuration: configuration,
            baseBlobOID: nil,
            headBlobOID: nil,
        )
        if let cached = try await store.analysis(cacheKey: cacheKey),
           cached.headOID == workspace.summary.headOID
        {
            try Task.checkCancellation()
            return cached
        }

        let credential = try await credential(for: configuration.selection.provider)
        let budget = AnalysisRunBudgetController(limits: configuration.selection.budget)
        let tools = AnalysisRepositoryTools(
            github: github,
            repository: workspace.summary.id.repository,
            baseOID: workspace.baseOID,
            headOID: workspace.summary.headOID,
            budget: budget,
        )
        let provider = makeProvider(
            selection: configuration.selection,
            credential: credential,
            tools: tools,
            budget: budget,
        )
        let chunks = ReviewAnalysisChunker.plan(
            workspace: workspace,
            reviewPlan: deterministicPlan,
            budget: configuration.selection.budget,
        )
        var hunkResults: [AIHunkAnalysis] = []
        var fileResults: [AIFileRollup] = []
        var summaries: [String] = []
        var usage = AnalysisUsage.zero

        for request in chunks.requests {
            try Task.checkCancellation()
            do {
                let value = try await provider.analyze(request)
                try Task.checkCancellation()
                hunkResults.append(contentsOf: value.hunks)
                fileResults.append(contentsOf: value.files)
                summaries.append(value.summary)
                usage = usage.adding(value.usage)
            } catch AIAnalysisError.providerCallLimitReached {
                break
            }
        }

        let toolMetrics = await budget.toolMetrics()
        usage = AnalysisUsage(
            promptTokens: usage.promptTokens,
            cachedPromptTokens: usage.cachedPromptTokens,
            outputTokens: usage.outputTokens,
            reasoningTokens: usage.reasoningTokens,
            providerCalls: usage.providerCalls,
            toolCalls: toolMetrics.toolCalls,
            filesRetrieved: toolMetrics.filesRetrieved,
            bytesRetrieved: toolMetrics.bytesRetrieved,
            durationMilliseconds: usage.durationMilliseconds,
            requestID: usage.requestID,
        )
        let analysis = ReviewAnalysis(
            hunks: hunkResults,
            files: coalescedFiles(fileResults),
            summary: summaries.isEmpty
                ? "The provider did not analyze any text hunks within this preset's budget."
                : summaries.joined(separator: "\n\n"),
            usage: usage,
        )
        let run = ReviewAnalysisRun(
            provider: configuration.selection.provider,
            preset: configuration.selection.preset,
            modelID: configuration.selection.modelID,
            headOID: workspace.summary.headOID,
            analysis: analysis,
            createdAt: now(),
            isCacheHit: false,
        )
        try Task.checkCancellation()
        try await store.saveAnalysis(run, cacheKey: cacheKey)
        return run
    }

    public func analyzeImages(
        pair: SnapshotImagePair,
        workspace: PullRequestWorkspace,
        configuration: ReviewAnalysisConfiguration,
    ) async throws -> SnapshotImageAnalysisRun {
        try Task.checkCancellation()
        guard configuration.globallyEnabled, configuration.repositoryEnabled else {
            throw AIAnalysisError.consentRequired
        }
        guard configuration.imageAnalysisEnabled else {
            throw AIAnalysisError.imageConsentRequired
        }
        let cacheKey = try cacheKey(
            kind: .image,
            workspace: workspace,
            configuration: configuration,
            baseBlobOID: pair.base?.oid,
            headBlobOID: pair.head?.oid,
        )
        if let cached = try await store.imageAnalysis(cacheKey: cacheKey),
           cached.baseOID == pair.base?.oid,
           cached.headOID == pair.head?.oid
        {
            try Task.checkCancellation()
            return cached
        }

        let credential = try await credential(for: configuration.selection.provider)
        let budget = AnalysisRunBudgetController(limits: configuration.selection.budget)
        let tools = AnalysisRepositoryTools(
            github: github,
            repository: workspace.summary.id.repository,
            baseOID: workspace.baseOID,
            headOID: workspace.summary.headOID,
            budget: budget,
        )
        let provider = makeProvider(
            selection: configuration.selection,
            credential: credential,
            tools: tools,
            budget: budget,
        )
        let metrics: SnapshotDiffMetrics? = switch pair.comparison {
            case let .comparable(value, _): value
            case .dimensionMismatch, .none: nil
        }
        let analysis = try await provider.analyzeImages(SnapshotImageAnalysisRequest(
            path: pair.file.path,
            baseOID: pair.base?.oid,
            headOID: pair.head?.oid,
            basePNGData: pair.base?.data,
            headPNGData: pair.head?.data,
            metrics: metrics,
        ))
        try Task.checkCancellation()
        let run = SnapshotImageAnalysisRun(
            provider: configuration.selection.provider,
            preset: configuration.selection.preset,
            modelID: configuration.selection.modelID,
            baseOID: pair.base?.oid,
            headOID: pair.head?.oid,
            analysis: analysis,
            createdAt: now(),
            isCacheHit: false,
        )
        try Task.checkCancellation()
        try await store.saveImageAnalysis(run, cacheKey: cacheKey)
        return run
    }

    public static func policyFingerprint(
        workspace: PullRequestWorkspace,
        settings: PatchlightRepositorySettings,
    ) -> String {
        do {
            let data = try JSONEncoder.cacheIdentity.encode(PolicyIdentity(
                configuration: workspace.repositoryConfiguration,
                overrides: settings.overrides,
            ))
            return digest(data)
        } catch {
            assertionFailure("Patchlight policy identity must remain encodable: \(error)")
            return digest(Data("invalid-policy".utf8))
        }
    }

    private func credential(for provider: AIProvider) async throws -> ProviderAPIKey {
        guard let value = try await credentials.credential(for: provider) else {
            throw AIAnalysisError.credentialMissing(provider)
        }
        return value
    }

    private func makeProvider(
        selection: AnalysisModelSelection,
        credential: ProviderAPIKey,
        tools: AnalysisRepositoryTools,
        budget: AnalysisRunBudgetController,
    ) -> any ReviewAnalysisProvider {
        switch selection.provider {
            case .openAI:
                OpenAIReviewAnalysisProvider(
                    selection: selection,
                    credential: credential,
                    transport: transport,
                    tools: tools,
                    budget: budget,
                )
            case .anthropic:
                AnthropicReviewAnalysisProvider(
                    selection: selection,
                    credential: credential,
                    transport: transport,
                    tools: tools,
                    budget: budget,
                )
        }
    }

    private func cacheKey(
        kind: CacheKind,
        workspace: PullRequestWorkspace,
        configuration: ReviewAnalysisConfiguration,
        baseBlobOID: GitObjectID?,
        headBlobOID: GitObjectID?,
    ) throws -> String {
        let identity = CacheIdentity(
            kind: kind,
            accountID: accountID,
            repository: workspace.summary.id.repository,
            pullRequest: workspace.summary.id,
            headOID: workspace.summary.headOID,
            provider: configuration.selection.provider,
            modelID: configuration.selection.modelID,
            preset: configuration.selection.preset,
            schemaVersion: ReviewAnalysisRun.schemaVersion,
            policyFingerprint: configuration.policyFingerprint,
            imageAnalysisEnabled: configuration.imageAnalysisEnabled,
            baseBlobOID: baseBlobOID,
            headBlobOID: headBlobOID,
        )
        return try Self.digest(JSONEncoder.cacheIdentity.encode(identity))
    }

    private func coalescedFiles(_ values: [AIFileRollup]) -> [AIFileRollup] {
        var order: [String] = []
        var byPath: [String: AIFileRollup] = [:]
        for value in values {
            guard let existing = byPath[value.path] else {
                order.append(value.path)
                byPath[value.path] = value
                continue
            }
            byPath[value.path] = AIFileRollup(
                path: value.path,
                summary: existing.summary == value.summary
                    ? existing.summary
                    : "\(existing.summary)\n\n\(value.summary)",
                minimumDepth: min(existing.minimumDepth, value.minimumDepth),
            )
        }
        return order.compactMap { byPath[$0] }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private enum CacheKind: String, Codable {
        case review = "R"
        case image = "I"
    }

    private struct CacheIdentity: Codable {
        let kind: CacheKind
        let accountID: PatchlightAccountID
        let repository: RepositoryID
        let pullRequest: PullRequestID
        let headOID: GitObjectID
        let provider: AIProvider
        let modelID: String
        let preset: AnalysisPreset
        let schemaVersion: Int
        let policyFingerprint: String
        let imageAnalysisEnabled: Bool
        let baseBlobOID: GitObjectID?
        let headBlobOID: GitObjectID?
    }

    private struct PolicyIdentity: Codable {
        let configuration: RepositoryConfigurationState
        let overrides: PatchlightLocalRepositoryOverrides
    }
}

extension JSONEncoder {
    fileprivate static var cacheIdentity: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
