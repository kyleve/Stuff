import Foundation
import MCP
import PortholeCore

/// Converts between `PortholeValue` and the MCP SDK's `Value`, and renders
/// values as JSON text for tool results.
enum MCPValueBridge {
    static func toMCP(_ value: PortholeValue) -> Value {
        switch value {
            case .null: .null
            case let .bool(bool): .bool(bool)
            case let .int(int): .int(Int(int))
            case let .double(double): .double(double)
            case let .string(string): .string(string)
            case let .data(data): .string(data.base64EncodedString())
            case let .date(date): .string(PortholeMCPISO8601.string(from: date))
            case let .array(array): .array(array.map(toMCP))
            case let .object(object): .object(object.mapValues(toMCP))
        }
    }

    static func toPorthole(_ value: Value) -> PortholeValue {
        switch value {
            case .null: .null
            case let .bool(bool): .bool(bool)
            case let .int(int): .int(Int64(int))
            case let .double(double): .double(double)
            case let .string(string): .string(string)
            case let .data(_, data): .data(data)
            case let .array(array): .array(array.map(toPorthole))
            case let .object(object): .object(object.mapValues(toPorthole))
        }
    }

    /// Renders a value as JSON text (fragments allowed, sorted keys).
    static func jsonString(_ value: PortholeValue) -> String {
        let object = foundationObject(value)
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed],
        ), let string = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return string
    }

    private static func foundationObject(_ value: PortholeValue) -> Any {
        switch value {
            case .null: NSNull()
            case let .bool(bool): bool
            case let .int(int): int
            case let .double(double): double
            case let .string(string): string
            case let .data(data): ["$data": data.base64EncodedString()]
            case let .date(date): PortholeMCPISO8601.string(from: date)
            case let .array(array): array.map(foundationObject)
            case let .object(object): object.mapValues(foundationObject)
        }
    }

    /// Builds the `porthole_overview` payload from a manifest.
    static func overview(_ manifests: [ConnectorManifest]) -> PortholeValue {
        .array(manifests.map { manifest in
            .object([
                "id": .string(manifest.connector.id.rawValue),
                "title": .string(manifest.connector.title),
                "summary": .string(manifest.connector.summary),
                "version": .int(Int64(manifest.connector.version)),
                "actions": .array(manifest.actions.map { action in
                    .object([
                        "id": .string(action.id.rawValue),
                        "title": .string(action.title),
                        "summary": .string(action.summary),
                        "destructive": .bool(action.isDestructive),
                        "parameters": action.parameters.jsonSchema(),
                    ])
                }),
                "dataSources": .array(manifest.dataSources.map { source in
                    .object([
                        "id": .string(source.id.rawValue),
                        "title": .string(source.title),
                        "summary": .string(source.summary),
                        "subscribable": .bool(source.supportsSubscription),
                        "rowSchema": source.rowSchema.jsonSchema(),
                        "filters": source.filters.jsonSchema(),
                    ])
                }),
            ])
        })
    }

    /// Whether a data value is a PNG (magic bytes) — returned as MCP image
    /// content so an agent sees the screenshot directly.
    static func isPNG(_ data: Data) -> Bool {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        return data.count >= signature.count && Array(data.prefix(signature.count)) == signature
    }
}

enum PortholeMCPISO8601 {
    private nonisolated(unsafe) static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}
