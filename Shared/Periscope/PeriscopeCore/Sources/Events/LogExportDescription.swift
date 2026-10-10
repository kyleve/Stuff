/// One declaration drives lazy live projection and value-free persisted permissions.
/// Constructing a description never encodes its values.
public struct LogExportDescription: Sendable {
    public let schema: LogExportSchema
    private let project: @Sendable (LogExportPolicy) throws -> JSONValue

    private init(
        schema: LogExportSchema,
        project: @escaping @Sendable (LogExportPolicy) throws -> JSONValue,
    ) {
        self.schema = schema
        self.project = project
    }

    public init(_ value: some Encodable & Sendable) {
        if let structured = value as? any LogExportable {
            self = structured.exportDescription
        } else {
            self.init(schema: .value) { _ in try JSONValue.encoding(value) }
        }
    }

    public func exportedValue(using policy: LogExportPolicy) throws -> JSONValue {
        try project(policy)
    }

    public static func object(_ fields: [LogExportField]) -> Self {
        let keyed = Dictionary(uniqueKeysWithValues: fields.map { ($0.key.rawValue, $0) })
        return Self(schema: .object(keyed
                .mapValues { .gated($0.requirements, $0.description.schema) }))
        { policy in
            var values: [String: JSONValue] = [:]
            for (key, field) in keyed {
                if let value = try field.exportedValue(using: policy) { values[key] = value }
            }
            return .object(values)
        }
    }

    public static func object(_ values: [String: Self]) -> Self {
        Self(schema: .object(values.mapValues(\.schema))) { policy in
            try .object(values.mapValues { try $0.exportedValue(using: policy) })
        }
    }

    public static func array(_ values: [Self]) -> Self {
        Self(schema: .array(values.map(\.schema))) { policy in
            try .array(values.map { try $0.exportedValue(using: policy) })
        }
    }
}
