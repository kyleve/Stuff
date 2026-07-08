import Foundation

/// One node in the log hierarchy — the Periscope equivalent of an OTel
/// `InstrumentationScope`.
///
/// Scopes form a tree: each has a name and an optional parent, and its
/// ``ScopeID`` is derived deterministically from that path (see `ScopeID`),
/// so the same path is the same scope everywhere. Events reference scopes
/// many-to-many — normally one leaf scope, several when logs are linked.
public struct LogScope: Hashable, Codable, Sendable, Identifiable {
    public let id: ScopeID
    public let name: String
    public let parentID: ScopeID?

    /// A root scope (no parent) with the given name.
    public static func root(named name: String) -> LogScope {
        LogScope(id: .derive(parent: nil, name: name), name: name, parentID: nil)
    }

    /// A child of this scope with the given name.
    public func child(named name: String) -> LogScope {
        LogScope(id: .derive(parent: id, name: name), name: name, parentID: id)
    }
}
