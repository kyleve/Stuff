import Foundation
import PortholeCore

public enum PortholeAgentToolRole: Sendable {}
public enum PortholeAgentCallRole: Sendable {}
public typealias PortholeAgentToolID = PortholeIdentifier<PortholeAgentToolRole>
public typealias PortholeAgentCallID = PortholeIdentifier<PortholeAgentCallRole>

/// A provider-neutral tool schema. The common dispatcher enforces its policy.
public struct PortholeAgentTool: Sendable, Equatable {
    public let toolID: PortholeAgentToolID
    public let description: String
    public let inputSchema: PortholeValue

    public init(toolID: PortholeAgentToolID, description: String, inputSchema: PortholeValue) {
        self.toolID = toolID
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// The provider's call identity stays stable while the dispatcher awaits approval.
public struct PortholeAgentInvocation: Sendable, Equatable, Codable {
    public let operationID: UUID
    public let callID: PortholeAgentCallID
    public let toolID: PortholeAgentToolID
    public let arguments: PortholeValue

    public init(
        operationID: UUID,
        callID: PortholeAgentCallID,
        toolID: PortholeAgentToolID,
        arguments: PortholeValue,
    ) {
        self.operationID = operationID
        self.callID = callID
        self.toolID = toolID
        self.arguments = arguments
    }
}

public struct PortholeAgentToolResult: Sendable, Equatable, Codable {
    public let callID: PortholeAgentCallID
    public let toolID: PortholeAgentToolID
    public let output: PortholeValue
    public let isError: Bool

    public init(
        callID: PortholeAgentCallID,
        toolID: PortholeAgentToolID,
        output: PortholeValue,
        isError: Bool,
    ) {
        self.callID = callID
        self.toolID = toolID
        self.output = output
        self.isError = isError
    }
}
