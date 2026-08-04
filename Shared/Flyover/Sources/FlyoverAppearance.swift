/// The color-scheme override applied to registered screens.
public enum FlyoverAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
        }
    }
}
