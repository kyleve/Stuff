import BroadwayCore
import BroadwayUI
import SwiftUI
import Testing
import UIKit
import ViewDocumentCore

@MainActor
struct BViewDocumentStylesheetTests {
    @Test(arguments: [UIUserInterfaceLevel.base, .elevated])
    func backgroundLevelsPinModeAndContrastButRetainHostElevation(level: UIUserInterfaceLevel) {
        var traits = BTraits()
        traits.mode = .dark
        traits.accessibility = .init(isDarkerSystemColorsEnabled: true)
        let appearance = BViewDocumentStylesheet(traits: traits).appearance
        let host = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: .light),
            UITraitCollection(accessibilityContrast: .normal),
            UITraitCollection(userInterfaceLevel: level),
        ])
        let expected = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: .dark),
            UITraitCollection(accessibilityContrast: .high),
            UITraitCollection(userInterfaceLevel: level),
        ])
        #expect(UIColor(appearance.color(.semantic(.background))).resolvedColor(with: host)
            == UIColor.systemBackground.resolvedColor(with: expected))
        #expect(UIColor(appearance.color(.semantic(.secondaryBackground))).resolvedColor(with: host)
            == UIColor.secondarySystemBackground.resolvedColor(with: expected))
        #expect(UIColor(appearance.color(.semantic(.secondaryGroupedBackground)))
            .resolvedColor(with: host)
            == UIColor.secondarySystemGroupedBackground.resolvedColor(with: expected))
        #expect(appearance.background == BViewDocumentStylesheet(traits: traits).appearance
            .background)
    }

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
        #expect(BViewDocumentStylesheet(traits: traits).shows(.essential))
        #expect(!BViewDocumentStylesheet(traits: traits).shows(.ornament))
        traits.accessibility = .init(isDarkerSystemColorsEnabled: true)
        #expect(!BViewDocumentStylesheet(traits: traits).showsDecoration)
        #expect(BViewDocumentStylesheet(traits: traits).shows(.essential))
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
