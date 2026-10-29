import SwiftUI
import Testing
import ViewDocumentCore
import ViewDocumentUI

struct ViewDocumentAppearanceTests {
    @Test func preservesSystemWeightUnlessExplicitlyOverridden() {
        let semantic = ViewFontDescriptor(
            size: .semantic(.headline),
            weight: nil,
            design: nil,
        )
        #expect(semantic.font == Font.headline)
        let regular = ViewFontDescriptor(
            size: .semantic(.headline),
            weight: .regular,
            design: nil,
        )
        #expect(regular.font == Font.headline.weight(.regular))
        #expect(regular.font != semantic.font)
    }

    @Test func scalesOnlyAuthoredSemanticDimensions() {
        let appearance = ViewDocumentAppearance(background: .white, dimensionScales: [.body: 2])
        #expect(appearance.dimension(.points(12)) == 12)
        #expect(appearance.dimension(.scaled(points: 12, relativeTo: .body)) == 24)
    }
}
