import Foundation

public enum PortholeEffect: String, Sendable, Codable {
    case read
    case isolated
    case mutation
    case unknown

    public var requiresApproval: Bool {
        switch self {
            case .read, .isolated: false
            case .mutation, .unknown: true
        }
    }
}

public enum PortholeAvailability: Sendable, Equatable, Codable {
    case callable
    case inspectable
    case unsupported(String)
}

public struct PortholeSourceLocation: Sendable, Equatable, Codable {
    public let path: String
    public let line: Int

    public init(path: String, line: Int) {
        self.path = path
        self.line = line
    }
}

/// A discoverable API's description does not grant permission to invoke it.
public struct PortholeCapability: Sendable, Equatable, Codable, Identifiable {
    public let id: PortholeSymbolID
    public let module: PortholeModuleID
    public let name: String
    public let summary: String
    public let parameters: [PortholeParameter]
    public let result: PortholeSchema
    public let effect: PortholeEffect
    public let source: PortholeSourceLocation?
    public let ownership: PortholeExecutionOwnership
    public let availability: PortholeAvailability

    public init(
        id: PortholeSymbolID,
        module: PortholeModuleID,
        name: String,
        summary: String,
        parameters: [PortholeParameter],
        result: PortholeSchema,
        effect: PortholeEffect,
        source: PortholeSourceLocation?,
        ownership: PortholeExecutionOwnership,
        availability: PortholeAvailability,
    ) {
        self.id = id
        self.module = module
        self.name = name
        self.summary = summary
        self.parameters = parameters
        self.result = result
        self.effect = effect
        self.source = source
        self.ownership = ownership
        self.availability = availability
    }
}
