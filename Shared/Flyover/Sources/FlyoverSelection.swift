/// The optional item used to present one registered screen in the focused inspector.
struct FlyoverSelection<ScreenID: Hashable>: Identifiable {
    let id: ScreenID
}
