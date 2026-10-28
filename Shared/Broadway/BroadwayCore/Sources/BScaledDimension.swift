import UIKit

/// Scales authored geometry against the slice's category, never ambient UIKit traits.
public enum BScaledDimension {
    public static func value(
        _ value: CGFloat,
        relativeTo textStyle: UIFont.TextStyle,
        category: BContentSizeCategory,
    ) -> CGFloat {
        UIFontMetrics(forTextStyle: textStyle).scaledValue(
            for: value,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: category
                .uiContentSizeCategory),
        )
    }
}
