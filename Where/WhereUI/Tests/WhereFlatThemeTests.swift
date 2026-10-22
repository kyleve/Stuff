import BroadwayCore
import SwiftUI
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct WhereFlatThemeTests {
    @Test(arguments: [BMode.light, .dark], [false, true])
    func resolvesModeAndContrast(mode: BMode, increasedContrast: Bool) throws {
        var traits = BTraits.system
        traits.mode = mode
        traits.accessibility = BAccessibility(isDarkerSystemColorsEnabled: increasedContrast)
        let overrides = WhereFlatTheme.overrides(traits: traits, base: .default)
        let surface = try #require(overrides.card.regular.surface)
        guard case let .matte(matte) = surface else {
            Issue.record("Flat requires an opaque matte surface")
            return
        }
        #expect(matte.fill.base == (mode == .light ? Color.white : .black))
        #expect(matte.fill.tintMix == (mode == .light ? 0.52 : 0.58))
        #expect(matte.outline.opacity == (increasedContrast ? 0.65 : (mode == .light ? 0.32 : 0.4)))
        #expect(matte.outline.width == (increasedContrast ? 1.5 : 1))
        #expect(overrides.card.regular.contentTint?.fraction == (increasedContrast ? 0.75 : 0.6))
    }

    @Test func inheritsPaperAndPrivacyOutlineFromSuppliedBase() throws {
        var base = WhereStylesheet.default
        base.card.elsewherePaper.surface.fill.base = .purple
        base.privacyPassportCard.outlineOpacity = 0.83
        base.privacyPassportCard.outlineWidth = 2.25
        var traits = BTraits.system
        traits.accessibility = BAccessibility()
        let overrides = WhereFlatTheme.overrides(traits: traits, base: base)
        let elsewhere = try #require(overrides.elsewhere.surface)
        let privacy = try #require(overrides.privacy.surface)
        guard case let .matte(passport) = privacy else {
            Issue.record("Flat requires matte paper and passport surfaces")
            return
        }
        #expect(elsewhere.fill.base == .purple)
        #expect(passport.outline.opacity == 0.83)
        #expect(passport.outline.width == 2.25)
    }

    @Test(arguments: [BMode.light, .dark], [false, true])
    func themeAssemblyPreservesSharedTraitResults(mode: BMode, reduceTransparency: Bool) throws {
        var traits = BTraits.system
        traits.mode = mode
        traits.contentSizeCategory = .accessibilityExtraExtraExtraLarge
        traits.accessibility = BAccessibility(
            isReduceMotionEnabled: true,
            isReduceTransparencyEnabled: reduceTransparency,
        )
        let standardContext = BContext(
            traits: traits,
            themes: WhereThemes.current(theme: .standard),
        )
        let flatContext = BContext(traits: traits, themes: WhereThemes.current(theme: .alternate))
        let base = try standardContext.stylesheets.get(WhereStylesheet.self)
        let flat = try flatContext.stylesheets.get(WhereStylesheet.self)
        #expect(flat.onboarding.usesOpaqueSurfaces)
        #expect(flat.onboarding.showsArtwork == base.onboarding.showsArtwork)
        #expect(flat.locationForecast.header.layout == base.locationForecast.header.layout)
        #expect(flat.locationWelcome.motion == base.locationWelcome.motion)
        #expect(flat.locationsBackground == base.locationsBackground)
        #expect(flat.card.regular.padding == base.card.regular.padding)
        #expect(flat.calendar == base.calendar)
        guard case let .matte(paper) = flat.card[.elsewhere].surface else {
            Issue.record("Flat must resolve after shared traits")
            return
        }
        #expect(paper.fill.base == base.card.elsewherePaper.surface.fill.base)
        #expect(paper.shadow.radius == 8)
        #expect(flat.card[.elsewhere].glow.opacity == 0)
        #expect(flat.card[.elsewhere].lift.opacity == 0)
        #expect(flat.card[.elsewhere].contentTint == base.card[.elsewhere].contentTint)
        #expect(flat.card[.elsewhere].showsProgress == false)
    }
}
