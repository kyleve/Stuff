import Foundation

public enum PortholeAgentProvider: String, Sendable, Codable, CaseIterable {
    case openAI = "openai"
    case anthropic
}

/// Provider settings contain no credentials. The caller selects the model explicitly.
public struct PortholeAgentConfiguration: Sendable, Equatable {
    public let provider: PortholeAgentProvider
    public let modelID: String
    public let instructions: String
    public let maxSteps: Int
    public let maxOutputTokens: Int
    public let duration: Duration

    public init(
        provider: PortholeAgentProvider,
        modelID: String,
        instructions: String,
        maxSteps: Int,
        maxOutputTokens: Int,
        duration: Duration,
    ) {
        self.provider = provider
        self.modelID = modelID
        self.instructions = instructions
        self.maxSteps = maxSteps
        self.maxOutputTokens = maxOutputTokens
        self.duration = duration
    }

    var isValid: Bool {
        !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && maxSteps > 0 && maxOutputTokens > 0 && duration > .zero
    }
}

public enum PortholeAgentError: Error, Sendable, Equatable {
    case busy
    case invalidConfiguration
    case invalidTool(String)
    case missingCredential(PortholeAgentProvider)
    case credentialStorage(Int32)
    case unsafeInteger
    case invalidNumber
    case toolFailed(String)
    case unexpectedApprovalRequest
    case consumerTooSlow
    case outputTooLarge
    case incompleteResponse
    case consentRequired(PortholeAgentProvider)
    case unsupportedJournalVersion(Int)
    case operationUnresolved(UUID)
    case operationMismatch
    case redactedFailure(String)
}
