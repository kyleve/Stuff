import SwiftUI
import UIKit

extension SnapshotConfiguration {
    /// A `UITraitCollection` expressing this configuration's appearance axes —
    /// interface style, content size category, contrast, layout direction, and
    /// legibility weight. Used both by the preview cutsheet's trait override and
    /// by the test runner to configure the capture, so the two stay in lockstep.
    public var uiTraitCollection: UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light),
            UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicType)),
            UITraitCollection(accessibilityContrast: contrast == .increased ? .high : .normal),
            UITraitCollection(
                layoutDirection: layoutDirection == .rightToLeft ? .rightToLeft : .leftToRight,
            ),
            UITraitCollection(
                legibilityWeight: legibilityWeight == .bold ? .bold : .regular,
            ),
        ])
    }
}

extension SnapshotConfiguration.Frame.Insets {
    /// The UIKit edge-insets value the capture pipeline's safe-area override
    /// consumes. Leading/trailing map to left/right — simulated insets are
    /// physical-edge chrome (status bar, home indicator), not text direction.
    public var uiEdgeInsets: UIEdgeInsets {
        UIEdgeInsets(top: top, left: leading, bottom: bottom, right: trailing)
    }
}

extension UIContentSizeCategory {
    /// Bridges a SwiftUI ``DynamicTypeSize`` to its UIKit content size category so
    /// a configuration's Dynamic Type axis can be applied via a trait collection.
    init(_ dynamicType: DynamicTypeSize) {
        self = switch dynamicType {
            case .xSmall: .extraSmall
            case .small: .small
            case .medium: .medium
            case .large: .large
            case .xLarge: .extraLarge
            case .xxLarge: .extraExtraLarge
            case .xxxLarge: .extraExtraExtraLarge
            case .accessibility1: .accessibilityMedium
            case .accessibility2: .accessibilityLarge
            case .accessibility3: .accessibilityExtraLarge
            case .accessibility4: .accessibilityExtraExtraLarge
            case .accessibility5: .accessibilityExtraExtraExtraLarge
            @unknown default: .large
        }
    }
}
