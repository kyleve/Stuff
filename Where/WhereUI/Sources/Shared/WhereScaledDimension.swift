import BroadwayCore
import UIKit

/// Scales authored geometry against the slice's category, never ambient UIKit traits.
enum WhereScaledDimension {
    static func value(
        _ value: CGFloat,
        relativeTo textStyle: UIFont.TextStyle,
        category: BContentSizeCategory,
    ) -> CGFloat {
        UIFontMetrics(forTextStyle: textStyle).scaledValue(
            for: value,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: uiCategory(category)),
        )
    }

    private static func uiCategory(_ category: BContentSizeCategory) -> UIContentSizeCategory {
        switch category {
            case .extraSmall: .extraSmall
            case .small: .small
            case .medium: .medium
            case .large: .large
            case .extraLarge: .extraLarge
            case .extraExtraLarge: .extraExtraLarge
            case .extraExtraExtraLarge: .extraExtraExtraLarge
            case .accessibilityMedium: .accessibilityMedium
            case .accessibilityLarge: .accessibilityLarge
            case .accessibilityExtraLarge: .accessibilityExtraLarge
            case .accessibilityExtraExtraLarge: .accessibilityExtraExtraLarge
            case .accessibilityExtraExtraExtraLarge: .accessibilityExtraExtraExtraLarge
        }
    }
}
