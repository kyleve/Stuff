import SwiftUI
import UIKit

extension SnapshotConfiguration {
    /// A `UITraitCollection` expressing this configuration's appearance and optional layout
    /// traits. Preview and capture hosts share this mapping.
    public var uiTraitCollection: UITraitCollection {
        var collections = [
            UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light),
            UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicType)),
            UITraitCollection(accessibilityContrast: contrast == .increased ? .high : .normal),
            UITraitCollection(
                layoutDirection: layoutDirection == .rightToLeft ? .rightToLeft : .leftToRight,
            ),
            UITraitCollection(
                legibilityWeight: legibilityWeight == .bold ? .bold : .regular,
            ),
        ]
        if let traits = resolvedLayoutTraits {
            collections += [
                UITraitCollection(horizontalSizeClass: traits.horizontalSizeClass.uiSizeClass),
                UITraitCollection(verticalSizeClass: traits.verticalSizeClass.uiSizeClass),
                UITraitCollection(userInterfaceIdiom: traits.interfaceIdiom.uiIdiom),
            ]
        }
        return UITraitCollection(traitsFrom: collections)
    }

    /// Applies the same UIKit traits to preview and test hosts, before mounting content.
    @MainActor
    public func applyTraits(to host: UIViewController) {
        let traits = uiTraitCollection
        host.traitOverrides.userInterfaceStyle = traits.userInterfaceStyle
        host.traitOverrides.preferredContentSizeCategory = traits.preferredContentSizeCategory
        host.traitOverrides.accessibilityContrast = traits.accessibilityContrast
        host.traitOverrides.layoutDirection = traits.layoutDirection
        host.traitOverrides.legibilityWeight = traits.legibilityWeight
        if let layoutTraits = resolvedLayoutTraits {
            host.traitOverrides.horizontalSizeClass = layoutTraits.horizontalSizeClass.uiSizeClass
            host.traitOverrides.verticalSizeClass = layoutTraits.verticalSizeClass.uiSizeClass
            host.traitOverrides.userInterfaceIdiom = layoutTraits.interfaceIdiom.uiIdiom
        } else {
            host.traitOverrides.remove(UITraitHorizontalSizeClass.self)
            host.traitOverrides.remove(UITraitVerticalSizeClass.self)
            host.traitOverrides.remove(UITraitUserInterfaceIdiom.self)
        }
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
