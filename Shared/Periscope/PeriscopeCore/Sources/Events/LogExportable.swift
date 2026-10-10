/// A structured value that filters its members before encoding for export.
/// Opaque Codable values use the containing field's approval for their complete contents.
public protocol LogExportable: Sendable {
    func exportedValue(using policy: LogExportPolicy) throws -> JSONValue
}

/// One lazily encoded field. A denied field never invokes its encoder or nested projection.
public struct LogExportField: Sendable {
    public let key: LogFieldKey
    public let requirements: LogExportRequirements
    private let project: @Sendable (LogExportPolicy) throws -> JSONValue

    public init(
        _ key: LogFieldKey,
        value: some Encodable & Sendable,
        requirements: LogExportRequirements,
    ) {
        self.key = key
        self.requirements = requirements
        project = { policy in try Self.project(value, using: policy) }
    }

    public func exportedValue(using policy: LogExportPolicy) throws -> JSONValue? {
        guard policy.allows(requirements) else { return nil }
        return try project(policy)
    }

    public static func object(_ fields: [Self], using policy: LogExportPolicy) throws -> JSONValue {
        var values: [String: JSONValue] = [:]
        for field in fields {
            if let value = try field.exportedValue(using: policy) {
                precondition(values[field.key.rawValue] == nil, "Duplicate export field key")
                values[field.key.rawValue] = value
            }
        }
        return .object(values)
    }

    fileprivate static func project(
        _ value: some Encodable & Sendable,
        using policy: LogExportPolicy,
    ) throws -> JSONValue {
        if let structured = value as? any LogExportable {
            return try structured.exportedValue(using: policy)
        }
        return try JSONValue.encoding(value)
    }
}

/// Preserve nested policies through standard containers rather than invoking their raw Codable
/// path.
extension Optional: LogExportable where Wrapped: Encodable & LogExportable {
    public func exportedValue(using policy: LogExportPolicy) throws -> JSONValue {
        switch self {
            case let .some(value): try LogExportField.project(value, using: policy)
            case .none: .null
        }
    }
}

extension Array: LogExportable where Element: Encodable & LogExportable {
    public func exportedValue(using policy: LogExportPolicy) throws -> JSONValue {
        try .array(map { try LogExportField.project($0, using: policy) })
    }
}

extension Dictionary: LogExportable where Key == String, Value: Encodable & LogExportable {
    public func exportedValue(using policy: LogExportPolicy) throws -> JSONValue {
        try .object(mapValues { try LogExportField.project($0, using: policy) })
    }
}
