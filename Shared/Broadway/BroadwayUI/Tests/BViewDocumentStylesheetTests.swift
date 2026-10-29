import BroadwayCore
import BroadwayUI
import Testing
import ViewDocumentCore

@MainActor
struct BViewDocumentStylesheetTests {
    @Test func resolvesAccessibilityAndExplicitScaling() {
        var traits = BTraits.system
        traits.contentSizeCategory = .large
        let standard = BViewDocumentStylesheet(traits: traits)
        #expect(standard.showsDecoration)
        #expect(!standard.motionIsStatic)
        traits.contentSizeCategory = .accessibilityExtraExtraExtraLarge
        traits.accessibility = .init(isReduceMotionEnabled: true)
        let accessible = BViewDocumentStylesheet(traits: traits)
        #expect(accessible.motionIsStatic)
        #expect(accessible.dimensionScales[.body, default: 0] > standard.dimensionScales[
            .body,
            default: 0,
        ])
        traits.accessibility = .init(isReduceTransparencyEnabled: true)
        #expect(!BViewDocumentStylesheet(traits: traits).showsDecoration)
        traits.accessibility = .init(isDarkerSystemColorsEnabled: true)
        #expect(!BViewDocumentStylesheet(traits: traits).showsDecoration)
    }

    @Test func traitChangeResolvesNewCachedSlice() {
        var context = BContext(traits: .system)
        let initial = context.stylesheet(BViewDocumentStylesheet.self, fallback: .default)
        context.traitOverrides.accessibility = .init(isReduceMotionEnabled: true)
        let changed = context.stylesheet(BViewDocumentStylesheet.self, fallback: .default)
        #expect(!initial.motionIsStatic)
        #expect(changed.motionIsStatic)
    }
}
