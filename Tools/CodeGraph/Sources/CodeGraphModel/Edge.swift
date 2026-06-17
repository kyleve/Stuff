import Foundation

/// A directed relationship between two nodes.
public struct Edge: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    /// The "from" end: the subclass, the conforming type, or the type that owns
    /// the member through which the reference flows.
    public var source: String
    /// The "to" end: the superclass, the protocol, or the referenced type.
    public var target: String
    public var kind: EdgeKind
    /// The member (property / method / initializer) the relationship flowed
    /// through, when applicable — e.g. the property whose type is `target`.
    public var viaMemberID: String?
    /// How many distinct source occurrences were collapsed into this edge.
    public var count: Int

    public init(
        id: String,
        source: String,
        target: String,
        kind: EdgeKind,
        viaMemberID: String? = nil,
        count: Int = 1,
    ) {
        self.id = id
        self.source = source
        self.target = target
        self.kind = kind
        self.viaMemberID = viaMemberID
        self.count = count
    }
}

/// The semantic of an ``Edge``. The extractor records every kind it can find;
/// the viewer decides which to show.
public enum EdgeKind: String, Codable, Sendable, CaseIterable, Hashable {
    /// Subclass to superclass.
    case inheritance
    /// Conforming type to protocol.
    case conformance
    /// Overriding member to the member it overrides.
    case override
    /// Container to a nested type or member it owns.
    case member
    /// A type owns a stored / computed property of the target type.
    case propertyType
    /// A function or initializer references the target in its parameters or
    /// return type.
    case paramOrReturnType
    /// A type constructs, or is initialized with, the target.
    case construction
    /// A generic parameter is constrained to the target.
    case genericConstraint
    /// A protocol's associated type relates to the target.
    case associatedType
    /// A module depends on another module.
    case moduleDependency
    /// A cross-type reference not captured by a more specific kind.
    case reference

    /// Whether the relationship is structural (the classic UML "is-a" / nesting
    /// edges) as opposed to a usage / data-flow reference.
    public var isStructural: Bool {
        switch self {
            case .inheritance, .conformance, .override, .member, .moduleDependency:
                true
            case .propertyType, .paramOrReturnType, .construction, .genericConstraint,
                 .associatedType, .reference:
                false
        }
    }
}
