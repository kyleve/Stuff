/// A compile-time namespace for one stable logging scope.
public protocol LogScopeDefinition {
    associatedtype SpanName: Hashable & Sendable = String
    associatedtype LogMethods = EmptyLogMethods

    static var scopeName: String { get }
    static func makeLogMethods(_ log: Log<Self>) -> LogMethods
}

/// The method surface for a scope that declares no structured events.
public struct EmptyLogMethods: Sendable {
    public init() {}
}

extension LogScopeDefinition where LogMethods == EmptyLogMethods {
    public static func makeLogMethods(_: Log<Self>) -> EmptyLogMethods {
        EmptyLogMethods()
    }
}
