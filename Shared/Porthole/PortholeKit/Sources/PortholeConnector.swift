import Foundation
import PortholeCore

/// A source of app data and operations that an app registers with ``Porthole``.
/// Conform a type (e.g. `WhereConnector`) and return its actions and data
/// sources; the runtime advertises their descriptors and routes requests to the
/// handlers. Reference type so a connector can hold onto app services.
public protocol PortholeConnector: AnyObject, Sendable {
    var descriptor: PortholeConnectorDescriptor { get }
    func actions() -> [PortholeAction]
    func dataSources() -> [PortholeDataSource]
}

extension PortholeConnector {
    public func actions() -> [PortholeAction] {
        []
    }

    public func dataSources() -> [PortholeDataSource] {
        []
    }
}

/// One invocable operation: its descriptor (id, LLM-facing summary, parameter
/// schema, destructive flag) and the handler the runtime calls after validating
/// the parameters against the schema.
public struct PortholeAction: Sendable {
    public var descriptor: PortholeActionDescriptor
    public var handler: @Sendable (PortholeValue) async throws -> PortholeValue

    public init(
        descriptor: PortholeActionDescriptor,
        handler: @escaping @Sendable (PortholeValue) async throws -> PortholeValue,
    ) {
        self.descriptor = descriptor
        self.handler = handler
    }
}

/// One queryable (optionally subscribable) source of rows: its descriptor, a
/// paginated `fetch`, and — when `descriptor.supportsSubscription` is true — a
/// `subscribe` that vends a live stream of row values.
public struct PortholeDataSource: Sendable {
    public var descriptor: PortholeDataSourceDescriptor
    public var fetch: @Sendable (PortholeQuery) async throws -> PortholePage
    /// Non-nil iff `descriptor.supportsSubscription` — the runtime rejects a
    /// subscribe request for a source without it.
    public var subscribe: (@Sendable () -> AsyncStream<PortholeValue>)?

    public init(
        descriptor: PortholeDataSourceDescriptor,
        fetch: @escaping @Sendable (PortholeQuery) async throws -> PortholePage,
        subscribe: (@Sendable () -> AsyncStream<PortholeValue>)? = nil,
    ) {
        self.descriptor = descriptor
        self.fetch = fetch
        self.subscribe = subscribe
    }
}
