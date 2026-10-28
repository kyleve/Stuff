import SwiftUI

/// A concise set of representative Dynamic Type sizes for global inspection.
public enum FlyoverDynamicType: String, CaseIterable, Identifiable, Sendable {
    case small
    case large
    case extraExtraExtraLarge
    case accessibility3

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
            case .small: "Small"
            case .large: "Large"
            case .extraExtraExtraLarge: "XXXL"
            case .accessibility3: "Accessibility 3"
        }
    }

    var value: DynamicTypeSize {
        switch self {
            case .small: .small
            case .large: .large
            case .extraExtraExtraLarge: .xxxLarge
            case .accessibility3: .accessibility3
        }
    }
}
