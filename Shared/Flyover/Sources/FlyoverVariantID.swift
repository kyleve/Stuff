/// A stable identifier for one content variant of a Flyover screen.
public struct FlyoverVariantID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        precondition(rawValue.isEmpty == false, "A Flyover variant ID must not be empty.")
        self.rawValue = rawValue
    }
}
