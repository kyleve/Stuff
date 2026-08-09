import Foundation
import StuffCore

public enum AIProvider: String, CaseIterable, Codable, Sendable {
    case openAI = "O"
    case anthropic = "A"
}

public enum AnalysisPreset: String, CaseIterable, Codable, Sendable {
    case fast = "F"
    case balanced = "B"
    case deep = "D"
    case advanced = "A"
}

public enum AnalysisReasoningEffort: String, Codable, Sendable {
    case off
    case low
    case medium
    case high
}

public struct AnalysisBudget: Hashable, Codable, Sendable {
    public let diffBytes: Int
    public let extraContextBytes: Int
    public let maximumProviderCalls: Int
    public let maximumTurns: Int

    public init(
        diffBytes: Int,
        extraContextBytes: Int,
        maximumProviderCalls: Int,
        maximumTurns: Int,
    ) {
        precondition(diffBytes > 0 && extraContextBytes >= 0)
        precondition(maximumProviderCalls > 0 && maximumTurns > 0)
        self.diffBytes = diffBytes
        self.extraContextBytes = extraContextBytes
        self.maximumProviderCalls = maximumProviderCalls
        self.maximumTurns = maximumTurns
    }
}

public struct AnalysisModelSelection: Hashable, Codable, Sendable {
    public let provider: AIProvider
    public let preset: AnalysisPreset
    public let modelID: String
    public let reasoningEffort: AnalysisReasoningEffort
    public let budget: AnalysisBudget

    public init(
        provider: AIProvider,
        preset: AnalysisPreset,
        advancedModelID: String?,
    ) throws {
        self.provider = provider
        self.preset = preset
        let definition = try Self.definition(
            provider: provider,
            preset: preset,
            advancedModelID: advancedModelID,
        )
        modelID = definition.modelID
        reasoningEffort = definition.reasoningEffort
        budget = definition.budget
    }

    private static func definition(
        provider: AIProvider,
        preset: AnalysisPreset,
        advancedModelID: String?,
    ) throws -> Definition {
        let fastBudget = AnalysisBudget(
            diffBytes: 512 * 1024,
            extraContextBytes: 256 * 1024,
            maximumProviderCalls: 8,
            maximumTurns: 4,
        )
        let balancedBudget = AnalysisBudget(
            diffBytes: 2 * 1024 * 1024,
            extraContextBytes: 1024 * 1024,
            maximumProviderCalls: 16,
            maximumTurns: 6,
        )
        let deepBudget = AnalysisBudget(
            diffBytes: 8 * 1024 * 1024,
            extraContextBytes: 2 * 1024 * 1024,
            maximumProviderCalls: 32,
            maximumTurns: 8,
        )

        switch (provider, preset) {
            case (.openAI, .fast):
                return Definition(
                    modelID: "gpt-5.6-luna",
                    reasoningEffort: .low,
                    budget: fastBudget,
                )
            case (.openAI, .balanced):
                return Definition(
                    modelID: "gpt-5.6-terra",
                    reasoningEffort: .medium,
                    budget: balancedBudget,
                )
            case (.openAI, .deep):
                return Definition(
                    modelID: "gpt-5.6-sol",
                    reasoningEffort: .high,
                    budget: deepBudget,
                )
            case (.anthropic, .fast):
                return Definition(
                    modelID: "claude-haiku-4-5-20251001",
                    reasoningEffort: .off,
                    budget: fastBudget,
                )
            case (.anthropic, .balanced):
                return Definition(
                    modelID: "claude-sonnet-5",
                    reasoningEffort: .medium,
                    budget: balancedBudget,
                )
            case (.anthropic, .deep):
                return Definition(
                    modelID: "claude-opus-5",
                    reasoningEffort: .high,
                    budget: deepBudget,
                )
            case (_, .advanced):
                let modelID = advancedModelID?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !modelID.isEmpty, modelID.count <= 200 else {
                    throw AIAnalysisError.invalidAdvancedModelID
                }
                return Definition(
                    modelID: modelID,
                    reasoningEffort: .medium,
                    budget: balancedBudget,
                )
        }
    }

    private struct Definition {
        let modelID: String
        let reasoningEffort: AnalysisReasoningEffort
        let budget: AnalysisBudget
    }
}

/// A provider secret that deliberately has no printable or Codable conformance.
public struct ProviderAPIKey: Sendable {
    let value: String

    public init(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 4096 else {
            throw AIAnalysisError.invalidAPIKey
        }
        self.value = trimmed
    }
}

/// App-global BYOK credentials. These keys are independent of GitHub account
/// worlds and therefore survive an explicit GitHub sign-out.
public actor ProviderCredentialManager {
    private let store: any CredentialStore

    public init(store: any CredentialStore) {
        self.store = store
    }

    public func hasCredential(for provider: AIProvider) throws -> Bool {
        try store.data(for: Self.key(for: provider)) != nil
    }

    public func credential(for provider: AIProvider) throws -> ProviderAPIKey? {
        guard let data = try store.data(for: Self.key(for: provider)) else { return nil }
        guard let value = String(data: data, encoding: .utf8) else {
            throw AIAnalysisError.invalidStoredAPIKey
        }
        return try ProviderAPIKey(value)
    }

    public func set(_ credential: ProviderAPIKey, for provider: AIProvider) throws {
        try store.set(Data(credential.value.utf8), for: Self.key(for: provider))
    }

    public func remove(_ provider: AIProvider) throws {
        try store.remove(Self.key(for: provider))
    }

    public static func credentialKey(for provider: AIProvider) -> CredentialKey {
        key(for: provider)
    }

    private static func key(for provider: AIProvider) -> CredentialKey {
        switch provider {
            case .openAI: CredentialKey("provider.openai.api-key")
            case .anthropic: CredentialKey("provider.anthropic.api-key")
        }
    }
}

public struct ReviewAnalysisRequest: Hashable, Codable, Sendable {
    public let pullRequest: PullRequestID
    public let baseOID: GitObjectID
    public let headOID: GitObjectID
    public let files: [DiffFile]

    public init(
        pullRequest: PullRequestID,
        baseOID: GitObjectID,
        headOID: GitObjectID,
        files: [DiffFile],
    ) {
        self.pullRequest = pullRequest
        self.baseOID = baseOID
        self.headOID = headOID
        self.files = files
    }
}

public struct AIReviewFinding: Identifiable, Hashable, Codable, Sendable {
    public struct ID: RawRepresentable, Hashable, Codable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            precondition(!rawValue.isEmpty)
            self.rawValue = rawValue
        }
    }

    public let id: ID
    public let hunkID: DiffHunk.ID
    public let title: String
    public let body: String
    public let side: DiffSide?
    public let line: Int?

    public init(
        id: ID,
        hunkID: DiffHunk.ID,
        title: String,
        body: String,
        side: DiffSide?,
        line: Int?,
    ) {
        self.id = id
        self.hunkID = hunkID
        self.title = title
        self.body = body
        self.side = side
        self.line = line
    }
}

public struct AIHunkAnalysis: Hashable, Codable, Sendable {
    public let assessment: ReviewAssessment
    public let riskSignals: [String]
    public let testSignals: [String]
    public let findings: [AIReviewFinding]

    public init(
        assessment: ReviewAssessment,
        riskSignals: [String],
        testSignals: [String],
        findings: [AIReviewFinding],
    ) {
        self.assessment = assessment
        self.riskSignals = riskSignals
        self.testSignals = testSignals
        self.findings = findings
    }
}

public struct AIFileRollup: Hashable, Codable, Sendable {
    public let path: String
    public let summary: String
    public let minimumDepth: ReviewDepth

    public init(path: String, summary: String, minimumDepth: ReviewDepth) {
        self.path = path
        self.summary = summary
        self.minimumDepth = minimumDepth
    }
}

public struct AnalysisUsage: Hashable, Codable, Sendable {
    public let promptTokens: Int?
    public let cachedPromptTokens: Int?
    public let outputTokens: Int?
    public let reasoningTokens: Int?
    public let providerCalls: Int
    public let toolCalls: Int
    public let filesRetrieved: Int
    public let bytesRetrieved: Int
    public let durationMilliseconds: Int
    public let requestID: String?

    public init(
        promptTokens: Int?,
        cachedPromptTokens: Int?,
        outputTokens: Int?,
        reasoningTokens: Int?,
        providerCalls: Int,
        toolCalls: Int,
        filesRetrieved: Int,
        bytesRetrieved: Int,
        durationMilliseconds: Int,
        requestID: String?,
    ) {
        self.promptTokens = promptTokens
        self.cachedPromptTokens = cachedPromptTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.providerCalls = providerCalls
        self.toolCalls = toolCalls
        self.filesRetrieved = filesRetrieved
        self.bytesRetrieved = bytesRetrieved
        self.durationMilliseconds = durationMilliseconds
        self.requestID = requestID
    }

    public static let zero = AnalysisUsage(
        promptTokens: nil,
        cachedPromptTokens: nil,
        outputTokens: nil,
        reasoningTokens: nil,
        providerCalls: 0,
        toolCalls: 0,
        filesRetrieved: 0,
        bytesRetrieved: 0,
        durationMilliseconds: 0,
        requestID: nil,
    )

    public func adding(_ other: AnalysisUsage) -> AnalysisUsage {
        AnalysisUsage(
            promptTokens: Self.sum(promptTokens, other.promptTokens),
            cachedPromptTokens: Self.sum(cachedPromptTokens, other.cachedPromptTokens),
            outputTokens: Self.sum(outputTokens, other.outputTokens),
            reasoningTokens: Self.sum(reasoningTokens, other.reasoningTokens),
            providerCalls: providerCalls + other.providerCalls,
            toolCalls: toolCalls + other.toolCalls,
            filesRetrieved: filesRetrieved + other.filesRetrieved,
            bytesRetrieved: bytesRetrieved + other.bytesRetrieved,
            durationMilliseconds: durationMilliseconds + other.durationMilliseconds,
            requestID: other.requestID ?? requestID,
        )
    }

    private static func sum(_ lhs: Int?, _ rhs: Int?) -> Int? {
        guard lhs != nil || rhs != nil else { return nil }
        return (lhs ?? 0) + (rhs ?? 0)
    }
}

public struct ReviewAnalysis: Hashable, Codable, Sendable {
    public let hunks: [AIHunkAnalysis]
    public let files: [AIFileRollup]
    public let summary: String
    public let usage: AnalysisUsage

    public init(
        hunks: [AIHunkAnalysis],
        files: [AIFileRollup],
        summary: String,
        usage: AnalysisUsage,
    ) {
        self.hunks = hunks
        self.files = files
        self.summary = summary
        self.usage = usage
    }
}

public struct ReviewAnalysisRun: Hashable, Codable, Sendable {
    public static let schemaVersion = 1

    public let provider: AIProvider
    public let preset: AnalysisPreset
    public let modelID: String
    public let headOID: GitObjectID
    public let analysis: ReviewAnalysis
    public let createdAt: Date
    public let isCacheHit: Bool

    public init(
        provider: AIProvider,
        preset: AnalysisPreset,
        modelID: String,
        headOID: GitObjectID,
        analysis: ReviewAnalysis,
        createdAt: Date,
        isCacheHit: Bool,
    ) {
        self.provider = provider
        self.preset = preset
        self.modelID = modelID
        self.headOID = headOID
        self.analysis = analysis
        self.createdAt = createdAt
        self.isCacheHit = isCacheHit
    }
}

public struct ReviewAnalysisConfiguration: Hashable, Codable, Sendable {
    public let globallyEnabled: Bool
    public let repositoryEnabled: Bool
    public let imageAnalysisEnabled: Bool
    public let selection: AnalysisModelSelection
    public let policyFingerprint: String

    public init(
        globallyEnabled: Bool,
        repositoryEnabled: Bool,
        imageAnalysisEnabled: Bool,
        selection: AnalysisModelSelection,
        policyFingerprint: String,
    ) {
        precondition(!policyFingerprint.isEmpty)
        self.globallyEnabled = globallyEnabled
        self.repositoryEnabled = repositoryEnabled
        self.imageAnalysisEnabled = imageAnalysisEnabled
        self.selection = selection
        self.policyFingerprint = policyFingerprint
    }
}

public struct SnapshotImageAnalysisRequest: Sendable {
    public let path: String
    public let baseOID: GitObjectID?
    public let headOID: GitObjectID?
    public let basePNGData: Data?
    public let headPNGData: Data?
    public let metrics: SnapshotDiffMetrics?

    public init(
        path: String,
        baseOID: GitObjectID?,
        headOID: GitObjectID?,
        basePNGData: Data?,
        headPNGData: Data?,
        metrics: SnapshotDiffMetrics?,
    ) {
        self.path = path
        self.baseOID = baseOID
        self.headOID = headOID
        self.basePNGData = basePNGData
        self.headPNGData = headPNGData
        self.metrics = metrics
    }
}

public struct SnapshotImageFinding: Identifiable, Hashable, Codable, Sendable {
    public struct ID: RawRepresentable, Hashable, Codable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            precondition(!rawValue.isEmpty)
            self.rawValue = rawValue
        }
    }

    public let id: ID
    public let target: SnapshotAnnotationTarget
    public let rectangle: NormalizedRectangle
    public let label: String
    public let explanation: String
    public let confidence: Double

    public init(
        id: ID,
        target: SnapshotAnnotationTarget,
        rectangle: NormalizedRectangle,
        label: String,
        explanation: String,
        confidence: Double,
    ) {
        self.id = id
        self.target = target
        self.rectangle = rectangle
        self.label = label
        self.explanation = explanation
        self.confidence = min(max(confidence, 0), 1)
    }
}

public struct SnapshotImageAnalysis: Hashable, Codable, Sendable {
    public let summary: String
    public let findings: [SnapshotImageFinding]
    public let usage: AnalysisUsage

    public init(summary: String, findings: [SnapshotImageFinding], usage: AnalysisUsage) {
        self.summary = summary
        self.findings = findings
        self.usage = usage
    }
}

public struct SnapshotImageAnalysisRun: Hashable, Codable, Sendable {
    public let provider: AIProvider
    public let preset: AnalysisPreset
    public let modelID: String
    public let baseOID: GitObjectID?
    public let headOID: GitObjectID?
    public let analysis: SnapshotImageAnalysis
    public let createdAt: Date
    public let isCacheHit: Bool

    public init(
        provider: AIProvider,
        preset: AnalysisPreset,
        modelID: String,
        baseOID: GitObjectID?,
        headOID: GitObjectID?,
        analysis: SnapshotImageAnalysis,
        createdAt: Date,
        isCacheHit: Bool,
    ) {
        self.provider = provider
        self.preset = preset
        self.modelID = modelID
        self.baseOID = baseOID
        self.headOID = headOID
        self.analysis = analysis
        self.createdAt = createdAt
        self.isCacheHit = isCacheHit
    }
}

public protocol ReviewAnalysisProvider: Sendable {
    var provider: AIProvider { get }
    var modelID: String { get }
    func analyze(_ request: ReviewAnalysisRequest) async throws -> ReviewAnalysis
    func analyzeImages(_ request: SnapshotImageAnalysisRequest) async throws
        -> SnapshotImageAnalysis
}

public enum AIAnalysisError: LocalizedError, Equatable, Sendable {
    case invalidAPIKey
    case invalidStoredAPIKey
    case credentialMissing(AIProvider)
    case invalidAdvancedModelID
    case consentRequired
    case imageConsentRequired
    case providerCallLimitReached
    case turnLimitReached
    case contextBudgetExceeded
    case fileTooLarge
    case invalidToolRequest
    case invalidProviderResponse
    case providerFailure(statusCode: Int, message: String)
    case outputValidationFailed(String)

    public var errorDescription: String? {
        switch self {
            case .invalidAPIKey: "The API key is empty or invalid."
            case .invalidStoredAPIKey: "The stored provider API key is not valid UTF-8."
            case let .credentialMissing(provider):
                "No API key is stored for \(provider == .openAI ? "OpenAI" : "Anthropic")."
            case .invalidAdvancedModelID: "Enter an explicit provider model ID."
            case .consentRequired: "AI analysis is disabled until you opt in."
            case .imageConsentRequired: "Image analysis requires separate repository consent."
            case .providerCallLimitReached: "The preset's provider-call limit was reached."
            case .turnLimitReached: "The preset's tool-turn limit was reached."
            case .contextBudgetExceeded: "The preset's extra-context budget was reached."
            case .fileTooLarge: "Provider tools cannot read more than 256 KiB from one file."
            case .invalidToolRequest: "The provider requested an invalid or unavailable tool operation."
            case .invalidProviderResponse: "The provider returned an invalid response."
            case let .providerFailure(statusCode, message):
                "The provider returned HTTP \(statusCode): \(message)"
            case let .outputValidationFailed(message):
                "Provider output failed validation: \(message)"
        }
    }
}
