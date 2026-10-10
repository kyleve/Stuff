/// Describes permissions using the same JSON keys and container shape as the value's Codable
/// representation. Opaque Codable members inherit their containing field's approval in full.
public protocol LogExportable: Sendable {
    var exportDescription: LogExportDescription { get }
}

extension LogExportable {
    public func exportedValue(using policy: LogExportPolicy) throws -> JSONValue {
        try exportDescription.exportedValue(using: policy)
    }
}

/// One lazily encoded field. A denied field never invokes its encoder.
public struct LogExportField: Sendable {
    public let key: LogFieldKey
    public let requirements: LogExportRequirements
    let description: LogExportDescription

    public init(
        _ key: LogFieldKey,
        value: some Encodable & Sendable,
        requirements: LogExportRequirements,
    ) {
        self.key = key
        self.requirements = requirements
        description = LogExportDescription(value)
    }

    public func exportedValue(using policy: LogExportPolicy) throws -> JSONValue? {
        guard policy.allows(requirements) else { return nil }
        return try description.exportedValue(using: policy)
    }

    public static func object(_ fields: [Self], using policy: LogExportPolicy) throws -> JSONValue {
        try LogExportDescription.object(fields).exportedValue(using: policy)
    }
}

extension Optional: LogExportable where Wrapped: Encodable & LogExportable {
    public var exportDescription: LogExportDescription {
        switch self {
            case let .some(value): value.exportDescription
            case .none: LogExportDescription(JSONValue.null)
        }
    }
}

extension Array: LogExportable where Element: Encodable & LogExportable {
    public var exportDescription: LogExportDescription {
        .array(map(\.exportDescription))
    }
}

extension Dictionary: LogExportable where Key == String, Value: Encodable & LogExportable {
    public var exportDescription: LogExportDescription {
        .object(mapValues(\.exportDescription))
    }
}
