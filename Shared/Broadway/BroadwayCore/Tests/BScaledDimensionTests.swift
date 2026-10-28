@testable import BroadwayCore
import Testing
import UIKit

struct BScaledDimensionTests {
    @Test(arguments: [UIFont.TextStyle.body, .title2, .caption1])
    func usesExplicitCategoryInsteadOfAmbientTraits(textStyle: UIFont.TextStyle) {
        UITraitCollection(preferredContentSizeCategory: .extraSmall).performAsCurrent {
            let category = BContentSizeCategory.accessibilityExtraExtraExtraLarge
            let expected = UIFontMetrics(forTextStyle: textStyle).scaledValue(
                for: 52,
                compatibleWith: UITraitCollection(
                    preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge,
                ),
            )
            #expect(BScaledDimension
                .value(52, relativeTo: textStyle, category: category) == expected)
            #expect(BScaledDimension.value(52, relativeTo: textStyle, category: category) > 52)
        }
    }
}
