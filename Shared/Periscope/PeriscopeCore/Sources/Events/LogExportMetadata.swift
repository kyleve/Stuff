/// Versioned, value-free permissions captured beside a locally persisted payload.
public struct LogExportMetadata: Codable, Equatable, Sendable {
    public let version: Int
    public let payload: LogExportSchema

    public init(payload: LogExportSchema) {
        version = 1
        self.payload = payload
    }

    public func filtered(_ value: JSONValue, using policy: LogExportPolicy) throws -> JSONValue {
        guard version == 1 else { throw LogExportSchema.Failure.unsupportedVersion(version) }
        return try payload.filtered(value, using: policy) ?? .object([:])
    }
}

/// A recursive allowlist over raw JSON. Object keys and array positions belong to the recorded
/// value. Opaque Codable values remain atomic.
public indirect enum LogExportSchema: Equatable, Sendable {
    case value
    case object([String: LogExportSchema])
    case array([LogExportSchema])
    case gated(LogExportRequirements, LogExportSchema)

    public enum Failure: Error, Equatable {
        case unsupportedVersion(Int)
        case shapeMismatch
    }

    public func filtered(_ value: JSONValue, using policy: LogExportPolicy) throws -> JSONValue? {
        switch self {
            case .value: return value
            case let .gated(requirements, child):
                guard policy.allows(requirements) else { return nil }
                return try child.filtered(value, using: policy)
            case let .object(fields):
                guard case let .object(values) = value else { throw Failure.shapeMismatch }
                var result: [String: JSONValue] = [:]
                for (key, child) in fields {
                    // Synthesized Codable omits nil optionals; live projection emits JSON null.
                    if let filtered = try child.filtered(values[key] ?? .null, using: policy) {
                        result[key] = filtered
                    }
                }
                return .object(result)
            case let .array(children):
                guard case let .array(values) = value, children.count == values.count else {
                    throw Failure.shapeMismatch
                }
                return try .array(zip(children, values).map { child, raw in
                    try child.filtered(raw, using: policy) ?? .null
                })
        }
    }
}

/// Explicit tags decouple the persisted format from Swift associated-value encoding.
extension LogExportSchema: Codable {
    private enum CodingKeys: String, CodingKey { case type, fields, elements, requirement, child }
    private enum Kind: String, Codable { case value, object, array, gated }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
            case .value: self = .value
            case .object: self = try .object(container.decode([String: Self].self, forKey: .fields))
            case .array: self = try .array(container.decode([Self].self, forKey: .elements))
            case .gated:
                self = try .gated(
                    container.decode(LogExportRequirements.self, forKey: .requirement),
                    container.decode(Self.self, forKey: .child),
                )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case .value: try container.encode(Kind.value, forKey: .type)
            case let .object(fields):
                try container.encode(Kind.object, forKey: .type)
                try container.encode(fields, forKey: .fields)
            case let .array(elements):
                try container.encode(Kind.array, forKey: .type)
                try container.encode(elements, forKey: .elements)
            case let .gated(requirement, child):
                try container.encode(Kind.gated, forKey: .type)
                try container.encode(requirement, forKey: .requirement)
                try container.encode(child, forKey: .child)
        }
    }
}
