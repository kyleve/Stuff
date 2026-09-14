import Foundation

/// A generation changes whenever the application replaces the owning world.
public struct PortholeScopeToken: Sendable, Hashable, Codable {
    public let id: PortholeScopeID
    public let generation: UUID

    public init(id: PortholeScopeID, generation: UUID) {
        self.id = id
        self.generation = generation
    }
}

public struct PortholeObjectReference: Sendable, Hashable, Codable {
    public let id: UUID
    public let scope: PortholeScopeToken
    public let typeName: String

    public init(id: UUID, scope: PortholeScopeToken, typeName: String) {
        self.id = id
        self.scope = scope
        self.typeName = typeName
    }
}

public struct PortholeContextLink: Sendable, Equatable, Codable, Identifiable {
    public let id: PortholeContextID
    public let label: String
    public let relation: String

    public init(id: PortholeContextID, label: String, relation: String) {
        self.id = id
        self.label = label
        self.relation = relation
    }
}

/// Frozen selection and evidence remain readable after live references expire.
public struct PortholeContext: Sendable, Equatable, Codable, Identifiable {
    public let id: PortholeContextID
    public let title: String
    public let scope: PortholeScopeToken
    public let capturedAt: Date
    public let values: PortholeValue
    public let objects: [PortholeObjectReference]
    public let links: [PortholeContextLink]
    public let source: PortholeSourceLocation?

    public init(
        id: PortholeContextID,
        title: String,
        scope: PortholeScopeToken,
        capturedAt: Date,
        values: PortholeValue,
        objects: [PortholeObjectReference],
        links: [PortholeContextLink],
        source: PortholeSourceLocation?,
    ) {
        self.id = id
        self.title = title
        self.scope = scope
        self.capturedAt = capturedAt
        self.values = values
        self.objects = objects
        self.links = links
        self.source = source
    }
}
