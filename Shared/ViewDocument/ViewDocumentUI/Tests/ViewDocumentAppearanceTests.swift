import SwiftUI
import Testing
import ViewDocumentCore
import ViewDocumentUI

struct ViewDocumentAppearanceTests {
    @Test func backgroundLevelsUseHostInputsAndTheLegacyInitializerHasOneFallback() {
        let appearance = ViewDocumentAppearance(backgrounds: .init(
            primary: .red,
            secondary: .green,
            grouped: .blue,
            secondaryGrouped: .orange,
        ), dimensionScales: [:])
        #expect(appearance.color(.semantic(.secondaryBackground)) == Color.green)
        #expect(appearance.color(.semantic(.groupedBackground)) == Color.blue)
        #expect(appearance.color(.semantic(.secondaryGroupedBackground)) == Color.orange)
        let fallback = ViewDocumentAppearance(background: .purple, dimensionScales: [:])
        #expect(fallback.color(.semantic(.secondaryGroupedBackground)) == Color.purple)
    }

    @Test func decodedNativePaletteRetainsSystemAdaptation() throws {
        let decoded = try JSONDecoder().decode(
            ViewColorDescriptor.self,
            from: Data(#"{"opacity":{"_0":{"semantic":{"_0":"red"}},"_1":0.15}}"#.utf8),
        )
        let appearance = ViewDocumentAppearance(background: .white, dimensionScales: [:])
        #expect(appearance.color(decoded) == Color.red.opacity(0.15))
        #expect(appearance.color(.semantic(.orange)) == Color.orange)
    }

    @Test func preservesSemanticColorCompositions() {
        let appearance = ViewDocumentAppearance(background: .white, dimensionScales: [:])
        #expect(appearance.color(.opacity(.semantic(.primary), 0.12)) == Color.primary
            .opacity(0.12))
        #expect(appearance
            .color(.mix(.semantic(.primary), .semantic(.accent), fraction: 0.25)) == Color.primary
            .mix(
                with: .accentColor,
                by: 0.25,
                in: .perceptual,
            ))
    }

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
