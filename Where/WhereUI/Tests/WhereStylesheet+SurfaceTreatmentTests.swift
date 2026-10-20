import BroadwayCore
import SwiftUI
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct WhereStylesheetSurfaceTreatmentTests {
    @Test(arguments: [BMode.light, .dark], [
        BAccessibility(),
        BAccessibility(isDarkerSystemColorsEnabled: true),
        BAccessibility(isReduceTransparencyEnabled: true),
        BAccessibility(isReduceMotionEnabled: true),
        BAccessibility(
            isDarkerSystemColorsEnabled: true,
            isReduceMotionEnabled: true,
            isReduceTransparencyEnabled: true,
        ),
    ])
    func flatRetainsOpaqueDepthAcrossAccessibility(
        mode: BMode,
        accessibility: BAccessibility,
    ) throws {
        var themes = BThemes()
        themes[WhereTheme.self] = .alternate
        var context = BContext(traits: .system, themes: themes)
        context.traitOverrides.mode = mode
        context.traitOverrides.accessibility = accessibility
        let sheet = try context.stylesheets.get(WhereStylesheet.self)
        let surfaces = [
            sheet.card.regular.surface,
            sheet.card.compact.surface,
            sheet.card[.elsewhere].surface,
            sheet.locationWelcome.surface,
            sheet.locationWelcome.close.surface,
            sheet.privacyPassportCard.surface,
        ]
        for surface in surfaces {
            guard case let .matte(style) = surface else {
                Issue.record("Flat must not mount a reflective surface")
                continue
            }
            #expect(style.outline.width >= 1)
            #expect(style.outline.opacity > 0)
            if accessibility.isDarkerSystemColorsEnabled {
                #expect(style.outline.width == 1.5)
                #expect(style.outline.opacity == 0.65)
            }
            #expect(style.shadow.radius > 0)
            #expect(style.shadow.color != .clear)
            #expect(style.fill.color(tint: .orange).resolve(in: EnvironmentValues()).opacity == 1)
        }
        #expect(sheet.card.constellation.haloOpacity == 0)
        #expect(sheet.card.constellation.coreOpacity == WhereStylesheet.default.card.constellation
            .coreOpacity)
        #expect(sheet.locationForecast.ink.surfaceWashOpacity == 0)
        #expect(sheet.card.securityPrint.backgroundBlendMode == .normal)
        #expect(sheet.card
            .dayCount == (accessibility.isReduceMotionEnabled ? .reducedMotion : .standard))
        #expect(sheet.locationWelcome
            .motion == (accessibility.isReduceMotionEnabled ? .reduced : .standard))
    }

    @Test(arguments: [BMode.light, .dark])
    func matteZoomUsesTheRenderedShadow(mode: BMode) throws {
        var themes = BThemes()
        themes[WhereTheme.self] = .alternate
        var context = BContext(traits: .system, themes: themes)
        context.traitOverrides.mode = mode
        let sheet = try context.stylesheets.get(WhereStylesheet.self)
        let card = sheet.card.regular
        guard case let .matte(surface) = card.surface else {
            Issue.record("Expected a matte card")
            return
        }
        let elevation = card.transitionElevation(tint: .orange)
        #expect(elevation.glow.color == .clear)
        #expect(elevation.lift == surface.shadow)
    }

    @Test(arguments: [BMode.light, .dark], RegionColorToken.allCases)
    func matteContentInkContrastsWithEveryRegionFill(mode: BMode, color: RegionColorToken) throws {
        var themes = BThemes()
        themes[WhereTheme.self] = .alternate
        var context = BContext(traits: .system, themes: themes)
        context.traitOverrides.mode = mode
        let sheet = try context.stylesheets.get(WhereStylesheet.self)
        guard case let .matte(surface) = sheet.card.regular.surface else {
            Issue.record("Expected a matte card")
            return
        }
        var environment = EnvironmentValues()
        environment.colorScheme = mode == .dark ? .dark : .light
        let fill = surface.fill.color(tint: color.color).resolve(in: environment)
        let ink = sheet.card.regular.contentTint.apply(to: color.color).resolve(in: environment)
        let fillLuminance = luminance(fill)
        let inkLuminance = luminance(ink)
        let contrast = (max(fillLuminance, inkLuminance) + 0.05)
            / (min(fillLuminance, inkLuminance) + 0.05)
        #expect(contrast >= 4.5)
    }

    private func luminance(_ color: Color.Resolved) -> Double {
        func linear(_ channel: Float) -> Double {
            let value = Double(channel)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 *
            linear(color.blue)
    }
}
