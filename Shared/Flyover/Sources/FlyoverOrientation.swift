/// The orientation of Flyover's device-sized viewports.
public enum FlyoverOrientation: String, CaseIterable, Identifiable, Sendable {
    case portrait
    case landscape

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
            case .portrait: "Portrait"
            case .landscape: "Landscape"
        }
    }
}
