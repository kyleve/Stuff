import Foundation

/// Describes a connector to a client (and, through it, to an agent) without
/// exposing its handlers — the manifest half of a connector.
public struct PortholeConnectorDescriptor: Sendable, Codable, Equatable {
    public var id: PortholeConnectorID
    public var title: String
    public var summary: String
    public var version: Int

    public init(id: PortholeConnectorID, title: String, summary: String, version: Int) {
        self.id = id
        self.title = title
        self.summary = summary
        self.version = version
    }
}

/// Describes one action: its address-local id, human/LLM-facing copy, parameter
/// schema, and whether invoking it mutates state (surfaces as an MCP
/// destructive hint and a CLI confirmation).
public struct PortholeActionDescriptor: Sendable, Codable, Equatable {
    public var id: PortholeActionID
    public var title: String
    /// Written for an LLM audience — becomes the MCP tool description.
    public var summary: String
    public var parameters: PortholeSchema
    public var isDestructive: Bool

    public init(
        id: PortholeActionID,
        title: String,
        summary: String,
        parameters: PortholeSchema,
        isDestructive: Bool,
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.parameters = parameters
        self.isDestructive = isDestructive
    }
}

/// Describes one data source: its row shape, the filters it accepts, and whether
/// it can be subscribed to for a live stream.
public struct PortholeDataSourceDescriptor: Sendable, Codable, Equatable {
    public var id: PortholeDataSourceID
    public var title: String
    public var summary: String
    public var rowSchema: PortholeSchema
    /// Object schema describing the accepted filter keys.
    public var filters: PortholeSchema
    public var supportsSubscription: Bool

    public init(
        id: PortholeDataSourceID,
        title: String,
        summary: String,
        rowSchema: PortholeSchema,
        filters: PortholeSchema,
        supportsSubscription: Bool,
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.rowSchema = rowSchema
        self.filters = filters
        self.supportsSubscription = supportsSubscription
    }
}

/// The full advertised surface of one connector: its descriptor plus the
/// descriptors of every action and data source it exposes. Returned by
/// `listConnectors` and the client `manifest()`.
public struct ConnectorManifest: Sendable, Codable, Equatable {
    public var connector: PortholeConnectorDescriptor
    public var actions: [PortholeActionDescriptor]
    public var dataSources: [PortholeDataSourceDescriptor]

    public init(
        connector: PortholeConnectorDescriptor,
        actions: [PortholeActionDescriptor],
        dataSources: [PortholeDataSourceDescriptor],
    ) {
        self.connector = connector
        self.actions = actions
        self.dataSources = dataSources
    }
}
