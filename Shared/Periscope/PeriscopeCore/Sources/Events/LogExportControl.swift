/// A stable identity for an independently enabled export permission.
/// Consumers add controls with static members and namespaced identifiers.
public struct LogExportControl: Hashable, Sendable, Codable {
    public let rawValue: String

    public init(_ identifier: StaticString) {
        let value = String(describing: identifier)
        precondition(!value.isEmpty, "An export control requires a nonempty identifier")
        rawValue = value
    }

    public static let identifiers = Self("periscope.identifiers")
    public static let location = Self("periscope.location")
    public static let userContent = Self("periscope.user-content")
    /// Other personal data, including unstructured text that can contain personal data.
    /// This control does not grant identifiers, location, user content, or custom controls.
    public static let personalData = Self("periscope.personal-data")

    /// The persisted identity is a bare string, independent of the Swift property name.
    /// Unknown identifiers round-trip without becoming enabled automatically.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard !value.isEmpty else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "An export control requires a nonempty identifier",
            )
        }
        rawValue = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
