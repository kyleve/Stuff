/// A forward navigation relationship rendered between two registered screens.
public struct FlyoverTransition<ScreenID: Hashable> {
    public let source: ScreenID
    public let destination: ScreenID
    public let kind: Kind
    public let label: String?

    public init(
        from source: ScreenID,
        to destination: ScreenID,
        kind: Kind,
        label: String? = nil,
    ) {
        self.source = source
        self.destination = destination
        self.kind = kind
        self.label = label
    }

    public enum Kind: String, Equatable, Hashable, Sendable {
        case push
        case modal
    }
}
