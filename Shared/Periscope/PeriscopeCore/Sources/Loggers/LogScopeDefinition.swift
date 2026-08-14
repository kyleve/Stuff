/// A compile-time namespace for one stable logging scope.
public protocol LogScopeDefinition {
    associatedtype SpanName: Hashable & Sendable = String

    static var scopeName: String { get }
}
