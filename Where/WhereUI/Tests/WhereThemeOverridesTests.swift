import BroadwayCore
import SwiftUI
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct WhereThemeOverridesTests {
    @Test func emptyOverridesPreserveAnAdjustedBase() {
        var sheet = WhereStylesheet.default
        sheet.card.regular.cornerRadius = 37
        sheet.locationWelcome.glow.opacity = 0.43
        sheet.locationForecast.ink.surfaceWashOpacity = 0.71
        let original = sheet
        WhereThemeOverrides().apply(to: &sheet)
        #expect(sheet == original)
        #expect(WhereThemeOverrides.resolve(theme: .standard, traits: .system, base: sheet)
            == WhereThemeOverrides())
    }

    @Test func explicitZeroChangesOnlyTheSpecifiedField() {
        var sheet = WhereStylesheet.default
        sheet.card.regular.cornerRadius = 37
        sheet.locationWelcome.glow.opacity = 0.43
        var expected = sheet
        expected.locationWelcome.glow.opacity = 0
        expected.locationForecast.summary.shadowOpacity = 0

        var overrides = WhereThemeOverrides()
        overrides.welcome.glowOpacity = 0
        overrides.forecast.summaryShadowOpacity = 0
        overrides.apply(to: &sheet)
        #expect(sheet == expected)
    }

    @Test func componentOverridesDoNotReplaceSiblingState() {
        var sheet = WhereStylesheet.default
        sheet.card.regular.padding = 39
        sheet.card.compact.padding = 17
        sheet.card.dayCount = .reducedMotion
        let compact = sheet.card.compact
        var overrides = WhereThemeOverrides()
        overrides.card.regular.contentTint = .init(color: .purple, fraction: 0.5)
        overrides.apply(to: &sheet)
        #expect(sheet.card.regular.contentTint == .init(color: .purple, fraction: 0.5))
        #expect(sheet.card.regular.padding == 39)
        #expect(sheet.card.compact == compact)
        #expect(sheet.card.dayCount == .reducedMotion)
    }

    @Test func elsewhereSurfaceKeepsCompactGeometryAndOriginalTextTreatment() {
        var sheet = WhereStylesheet.default
        sheet.card.compact.padding = 17
        let original = sheet.card[.elsewhere]
        var surface = sheet.card.elsewherePaper.surface
        surface.outline.width = 2
        surface.shadow.radius = 8
        var overrides = WhereThemeOverrides()
        overrides.elsewhere.surface = surface
        overrides.apply(to: &sheet)
        let elsewhere = sheet.card[.elsewhere]
        #expect(elsewhere.surface == .matte(surface))
        #expect(elsewhere.padding == 17)
        #expect(elsewhere.contentTint == original.contentTint)
        #expect(elsewhere.showsProgress == false)
        #expect(sheet.card.compact.paper == nil)
    }
}
