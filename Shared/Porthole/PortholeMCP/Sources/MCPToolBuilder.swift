import Foundation
import PortholeCore

/// What a generated MCP tool maps to on the device.
public enum MCPToolTarget: Equatable, Sendable {
    case overview
    case action(PortholeActionRef)
    case query(PortholeDataSourceRef)
    case tail(PortholeDataSourceRef)
}

/// A tool the MCP server will expose, described independently of the MCP SDK
/// types so it can be planned and unit-tested purely. `inputSchema` is a
/// JSON-Schema object as a `PortholeValue`.
public struct PlannedTool: Equatable, Sendable {
    public var name: String
    public var description: String
    public var inputSchema: PortholeValue
    public var target: MCPToolTarget
}

/// Turns a device manifest into the MCP tool list (+ dispatch targets). Pure.
public enum MCPToolBuilder {
    /// Caps on the `tail_*` collection window, surfaced in the schema too.
    public static let maxTailDurationSeconds = 60
    public static let maxTailEvents = 500

    /// Lowercases and replaces every character outside `[a-z0-9_]` with `_`.
    public static func sanitize(_ string: String) -> String {
        String(string.lowercased().map { character in
            character.isNumber || ("a" ... "z")
                .contains(character) || character == "_" ? character : "_"
        })
    }

    public static func plan(from manifests: [ConnectorManifest]) -> [PlannedTool] {
        var tools: [PlannedTool] = [
            PlannedTool(
                name: "porthole_overview",
                description: "List every connector, action, and data source the app exposes, with their schemas. Call this first to discover what's available.",
                inputSchema: PortholeSchema.object([:]).jsonSchema(),
                target: .overview,
            ),
        ]

        for manifest in manifests {
            let connector = manifest.connector.id.rawValue
            for action in manifest.actions {
                let name = "act_\(sanitize(connector))_\(sanitize(action.id.rawValue))"
                var description = action.summary
                if action.isDestructive { description += " (Destructive: this changes app state.)" }
                tools.append(PlannedTool(
                    name: name,
                    description: description,
                    inputSchema: action.parameters.jsonSchema(),
                    target: .action(PortholeActionRef(
                        connector: manifest.connector.id,
                        action: action.id,
                    )),
                ))
            }
            for source in manifest.dataSources {
                let ref = PortholeDataSourceRef(connector: manifest.connector.id, source: source.id)
                tools.append(PlannedTool(
                    name: "query_\(sanitize(connector))_\(sanitize(source.id.rawValue))",
                    description: "\(source.summary) Returns a page of rows.",
                    inputSchema: querySchema(filters: source.filters),
                    target: .query(ref),
                ))
                if source.supportsSubscription {
                    tools.append(PlannedTool(
                        name: "tail_\(sanitize(connector))_\(sanitize(source.id.rawValue))",
                        description: "\(source.summary) Collects live events for a bounded window and returns them as an array.",
                        inputSchema: tailSchema(filters: source.filters),
                        target: .tail(ref),
                    ))
                }
            }
        }
        return tools
    }

    private static func querySchema(filters: PortholeSchema) -> PortholeValue {
        var properties = filters.properties ?? [:]
        properties["limit"] = .integer("Maximum number of rows to return")
        properties["cursor"] = .string("Opaque pagination cursor from a previous page")
        return PortholeSchema.object(properties).jsonSchema()
    }

    private static func tailSchema(filters: PortholeSchema) -> PortholeValue {
        var properties = filters.properties ?? [:]
        properties["durationSeconds"] =
            .integer("How long to collect events (max \(maxTailDurationSeconds))")
        properties["maxEvents"] = .integer("Maximum events to collect (max \(maxTailEvents))")
        return PortholeSchema.object(properties).jsonSchema()
    }
}
