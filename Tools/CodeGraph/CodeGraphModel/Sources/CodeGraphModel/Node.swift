import Foundation

/// A single vertex in the graph: a type, a member of a type, a free function, a
/// module, or an external (SDK / third-party) symbol referenced by the repo.
public struct Node: Codable, Sendable, Hashable, Identifiable {
    /// Stable identifier. For symbols this is the compiler USR; for modules it
    /// is the module name prefixed with `module:`.
    public var id: String
    /// Display name (unqualified), e.g. `WhereSession` or `report`.
    public var name: String
    public var kind: NodeKind
    /// Owning module name (e.g. `WhereCore`).
    public var module: String
    public var origin: Origin
    /// Owning node id (the enclosing type or module) for membership / nesting.
    public var parentID: String?
    /// Source file path, relative to the repo root when known.
    public var file: String?
    /// 1-based line of the declaration.
    public var line: Int?
    /// Whether the declaration introduces generic parameters.
    public var isGeneric: Bool

    public init(
        id: String,
        name: String,
        kind: NodeKind,
        module: String,
        origin: Origin,
        parentID: String? = nil,
        file: String? = nil,
        line: Int? = nil,
        isGeneric: Bool = false,
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.module = module
        self.origin = origin
        self.parentID = parentID
        self.file = file
        self.line = line
        self.isGeneric = isGeneric
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case module
        case origin
        case parentID
        case file
        case line
        case isGeneric
    }

    /// Custom decoding so that hand-written and older snapshots can omit
    /// naturally-defaulted fields (`isGeneric`) without failing to load.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(NodeKind.self, forKey: .kind)
        module = try container.decode(String.self, forKey: .module)
        origin = try container.decode(Origin.self, forKey: .origin)
        parentID = try container.decodeIfPresent(String.self, forKey: .parentID)
        file = try container.decodeIfPresent(String.self, forKey: .file)
        line = try container.decodeIfPresent(Int.self, forKey: .line)
        isGeneric = try container.decodeIfPresent(Bool.self, forKey: .isGeneric) ?? false
    }
}

/// The flavor of a ``Node``.
public enum NodeKind: String, Codable, Sendable, CaseIterable, Hashable {
    // Type declarations.
    case `class`
    case `struct`
    case `enum`
    case `protocol`
    case actor
    case `extension`
    case typeAlias = "typealias"
    case associatedType

    // Members / free declarations.
    case method
    case property
    case initializer
    case `subscript`
    case enumCase
    case function

    /// Grouping.
    case module

    case other

    /// Whether this kind is a nominal type — the primary nodes a UML-style view
    /// arranges (as opposed to members, modules, or loose declarations).
    public var isType: Bool {
        switch self {
            case .class, .struct, .enum, .protocol, .actor, .extension, .typeAlias,
                 .associatedType:
                true
            case .method, .property, .initializer, .subscript, .enumCase, .function,
                 .module, .other:
                false
        }
    }

    /// Whether this kind is a member of an enclosing type (and so hidden until
    /// its owner is expanded).
    public var isMember: Bool {
        switch self {
            case .method, .property, .initializer, .subscript, .enumCase:
                true
            case .class, .struct, .enum, .protocol, .actor, .extension, .typeAlias,
                 .associatedType, .function, .module, .other:
                false
        }
    }
}

/// Where a node's declaration lives relative to the repository.
public enum Origin: String, Codable, Sendable, CaseIterable, Hashable {
    /// Declared in the repository's production code.
    case firstParty
    /// Declared in a test target of the repository.
    case test
    /// Declared outside the repository (Apple SDK, third-party packages).
    case external
}
