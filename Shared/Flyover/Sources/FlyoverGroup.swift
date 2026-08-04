/// A named cluster of related Flyover screens with one graph root.
@MainActor
public struct FlyoverGroup<ScreenID: Hashable> {
    public let id: FlyoverGroupID
    public let title: String
    public let root: ScreenID
    public let screens: [FlyoverScreen<ScreenID>]

    public init(
        id: FlyoverGroupID,
        title: String,
        root: ScreenID,
        screens: [FlyoverScreen<ScreenID>],
    ) {
        precondition(screens.isEmpty == false, "A Flyover group must contain a screen.")
        self.id = id
        self.title = title
        self.root = root
        self.screens = screens
    }
}
