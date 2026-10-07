import Foundation

struct FlagDefinition {
    let id: FlagID
    let name: String
    let detail: String?
    let behavior: FeatureFlagBehaviorKind
    let defaultValue: JSONValue
    let source: FeatureFlagSourceMetadata
    let group: FeatureFlagGroupMetadata
    let decode: @Sendable (JSONValue) throws -> any Sendable

    init<Value, Behavior>(
        flag: Flag<Value, Behavior>,
        source: FeatureFlagSourceMetadata,
        group: FeatureFlagGroupMetadata,
    ) throws where Value: Codable & Sendable, Behavior: FeatureFlagBehavior {
        id = flag.id
        name = flag.name
        detail = flag.detail
        behavior = Behavior.kind
        defaultValue = try Self.json(flag.defaultValue)
        self.source = source
        self.group = group
        decode = { json in try Self.value(Value.self, from: json) }
    }

    static func json(_ value: some Encodable) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder.flagger.encode(value))
    }

    static func value<Value: Decodable>(_ type: Value.Type, from json: JSONValue) throws -> Value {
        try JSONDecoder().decode(type, from: JSONEncoder.flagger.encode(json))
    }
}
