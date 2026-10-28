/// A stable identifier for one visual group in a Flyover catalog.
public struct FlyoverGroupID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        precondition(rawValue.isEmpty == false, "A Flyover group ID must not be empty.")
        self.rawValue = rawValue
    }
}
