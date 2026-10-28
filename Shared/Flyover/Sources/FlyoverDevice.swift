import CoreGraphics

/// A device-sized viewport available to every registered screen.
public enum FlyoverDevice: String, CaseIterable, Identifiable, Sendable {
    case phone
    case tablet

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
            case .phone: "Phone"
            case .tablet: "Tablet"
        }
    }

    var portraitSize: CGSize {
        switch self {
            case .phone: CGSize(width: 402, height: 874)
            case .tablet: CGSize(width: 834, height: 1194)
        }
    }
}
