import BroadwayCore
import SwiftUI
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct WhereBundledThemesTests {
    @Test(arguments: WhereTheme.allCases)
    func everySavedThemePreparesThroughTheBundledCatalog(theme: WhereTheme) throws {
        let prepared = try WhereBundledThemes.prepared(theme)
        let resolved = try WhereBundledThemeDefinitions.resolved(theme)
        #expect(prepared.resolved == resolved)
        try resolved.appearance.requireComplete(path: "appearance")
        if theme == .halloween {
            #expect(resolved.id == .halloween)
            #expect(prepared.componentArtwork[.regularCard]?.isEmpty == false)
        }
    }

    @Test(arguments: [BMode.light, .dark], [false, true])
    func resolvesModeAndContrast(mode: BMode, increasedContrast: Bool) throws {
        var traits = BTraits.system
        traits.mode = mode
        traits.accessibility = BAccessibility(isDarkerSystemColorsEnabled: increasedContrast)
        let sheet = try WhereStylesheet(
            resolved: WhereBundledThemeDefinitions.resolved(.alternate),
            traits: traits,
        )
        let surface = sheet.card.regular.surface
        guard case let .matte(matte) = surface else {
            Issue.record("Flat requires an opaque matte surface")
            return
        }
        #expect(matte.fill.base == (mode == .light ? Color.white : .black))
        #expect(matte.fill.tintMix == (mode == .light ? 0.52 : 0.58))
        #expect(matte.outline.opacity == (increasedContrast ? 0.65 : (mode == .light ? 0.32 : 0.4)))
        #expect(matte.outline.width == (increasedContrast ? 1.5 : 1))
        #expect(sheet.card.regular.contentTint.fraction == (increasedContrast ? 0.75 : 0.6))
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
