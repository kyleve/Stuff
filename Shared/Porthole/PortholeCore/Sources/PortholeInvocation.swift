import Foundation

/// Reusing an operation identity never authorizes a different call or a retry of an uncertain
/// write.
public struct PortholeInvocation: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let scope: PortholeScopeToken
    public let capabilityID: PortholeSymbolID
    public let receiver: PortholeObjectReference?
    public let arguments: PortholeValue

    public init(
        id: UUID,
        scope: PortholeScopeToken,
        capabilityID: PortholeSymbolID,
        receiver: PortholeObjectReference?,
        arguments: PortholeValue,
    ) {
        self.id = id
        self.scope = scope
        self.capabilityID = capabilityID
        self.receiver = receiver
        self.arguments = arguments
    }
}

public struct PortholeActionProposal: Sendable, Equatable, Codable, Identifiable {
    public let invocation: PortholeInvocation
    public let capability: PortholeCapability
    public var id: UUID {
        invocation.id
    }

    public init(invocation: PortholeInvocation, capability: PortholeCapability) {
        self.invocation = invocation
        self.capability = capability
    }
}

public protocol PortholeExecuting: Sendable {
    func capabilities(in scope: PortholeScopeToken) async throws -> [PortholeCapability]
    func invoke(_ invocation: PortholeInvocation) async throws -> PortholeValue
}
