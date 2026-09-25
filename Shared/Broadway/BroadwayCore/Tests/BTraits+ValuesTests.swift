@testable import BroadwayCore
import Testing
import UIKit

struct BTraitsValuesTests {
    @Test(arguments: [
        UIContentSizeCategory.extraSmall,
        .small,
        .medium,
        .large,
        .extraLarge,
        .extraExtraLarge,
        .extraExtraExtraLarge,
        .accessibilityMedium,
        .accessibilityLarge,
        .accessibilityExtraLarge,
        .accessibilityExtraExtraLarge,
        .accessibilityExtraExtraExtraLarge,
    ])
    func contentSizeCategoryRoundTrips(category: UIContentSizeCategory) {
        #expect(BContentSizeCategory.from(category).uiContentSizeCategory == category)
    }
}
