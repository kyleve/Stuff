import Foundation
import PortholeCore

/// The journal owns durable conversation storage. Each request supplies its history.
public enum PortholeAgentMessage: Sendable, Equatable, Codable {
    public enum TextRole: Sendable { case user, assistant }
    case user(text: String)
    case assistant(text: String, toolCalls: [PortholeAgentInvocation])
    case tool(results: [PortholeAgentToolResult])

    // Explicit wire names keep synthesized coding stable across Swift-side renames.
    // swiftformat:disable redundantRawValues
    private enum CodingKeys: String,
        CodingKey { case user = "user", assistant = "assistant", tool = "tool" }
    private enum UserCodingKeys: String, CodingKey { case text = "text" }
    private enum AssistantCodingKeys: String,
        CodingKey { case text = "text", toolCalls = "toolCalls" }
    private enum ToolCodingKeys: String, CodingKey { case results = "results" }
    // swiftformat:enable redundantRawValues

    public init(role: TextRole, text: String) {
        switch role {
            case .user: self = .user(text: text)
            case .assistant: self = .assistant(text: text, toolCalls: [])
        }
    }
}

public struct PortholeAgentUsage: Sendable, Equatable {
    public let inputTokens: Int
    public let outputTokens: Int
}

public enum PortholeAgentFinishReason: String, Sendable {
    case stop, length, toolCalls, contentFilter, error, other
}

/// Only tool-visible data crosses this boundary; keys and SDK objects stay native.
public enum PortholeAgentEvent: Sendable, Equatable {
    case started(runID: UUID)
    case stepStarted(index: Int)
    case text(String)
    case reasoning(String)
    case toolInputStarted(callID: PortholeAgentCallID, toolID: PortholeAgentToolID)
    case toolInputDelta(callID: PortholeAgentCallID, json: String)
    case toolCall(PortholeAgentInvocation)
    case toolResult(callID: PortholeAgentCallID, value: PortholeValue, isError: Bool)
    case stepFinished(index: Int, usage: PortholeAgentUsage)
    case message(PortholeAgentMessage)
    case finished(
        runID: UUID,
        text: String,
        reason: PortholeAgentFinishReason,
        usage: PortholeAgentUsage,
    )
}
