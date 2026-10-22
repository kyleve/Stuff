/// The tab selection stays valid when the selected year's optional tab disappears.
struct MainTabSelection {
    enum TabID: Hashable {
        case locations
        case elsewhere
        case year
        case settings
    }

    var selected: TabID = .locations

    mutating func reconcile(hasElsewhere: Bool) {
        if selected == .elsewhere, !hasElsewhere { selected = .locations }
    }
}
