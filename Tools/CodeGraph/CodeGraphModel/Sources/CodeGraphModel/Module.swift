import Foundation

/// A build module (a SwiftPM / Tuist target) and the modules it depends on.
public struct Module: Codable, Sendable, Hashable, Identifiable {
    public var id: String {
        name
    }

    /// Module name, e.g. `WhereCore`.
    public var name: String
    public var kind: ModuleKind
    /// Names of the modules this module depends on.
    public var dependencies: [String]

    public init(name: String, kind: ModuleKind, dependencies: [String] = []) {
        self.name = name
        self.kind = kind
        self.dependencies = dependencies
    }
}

/// The role a ``Module`` plays in the build.
public enum ModuleKind: String, Codable, Sendable, CaseIterable, Hashable {
    case library
    case app
    case appExtension
    case test
    case external
    case unknown
}
