enum DashboardPresentation: Hashable, Identifiable {
    case preview
    case fullScreen

    var id: Self {
        self
    }
}
