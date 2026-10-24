import BroadwayCore
import SwiftUI

/// Flat's authored finish values, resolved over Standard's trait-adjusted base.
/// Region colors remain runtime inputs to the resolved surface descriptors.
enum WhereFlatTheme {
    static func overrides(traits: BTraits, base: WhereStylesheet) -> WhereThemeOverrides {
        let mode = traits.mode
        var overrides = WhereThemeOverrides()
        let increasedContrast = traits.accessibility.isDarkerSystemColorsEnabled
        let outline = WhereStylesheet.MatteSurface.Outline(
            opacity: increasedContrast ? 0.65 : BModeVarying(light: 0.32, dark: 0.4)[mode],
            width: increasedContrast ? 1.5 : 1,
        )
        let paper = WhereStylesheet.MatteSurface.Fill(
            base: BModeVarying(light: Color.white, dark: Color(white: 0.12))[mode],
            tintMix: 0,
        )
        let shadow = WhereStylesheet.MatteSurface.Shadow(
            color: .black.opacity(BModeVarying(light: 0.14, dark: 0.3)[mode]),
            radius: 10,
            offsetY: 4,
        )
        let regionSurface = WhereStylesheet.MatteSurface(
            fill: .init(
                base: BModeVarying(light: Color.white, dark: .black)[mode],
                tintMix: BModeVarying(light: 0.52, dark: 0.58)[mode],
            ),
            outline: outline,
            shadow: shadow,
            pressedTintOpacity: 0.1,
        )
        overrides.card.regular.surface = .matte(regionSurface)
        var compactSurface = regionSurface
        compactSurface.shadow.radius = 6
        compactSurface.shadow.offsetY = 3
        overrides.card.compact.surface = .matte(compactSurface)
        let contentTint = WhereStylesheet.TintAdjustment(
            color: BModeVarying(light: Color.black, dark: .white)[mode],
            fraction: increasedContrast ? 0.75 : 0.6,
        )
        overrides.card.regular.contentTint = contentTint
        overrides.card.compact.contentTint = contentTint
        overrides.card.haloOpacity = 0
        overrides.card.backgroundBlendMode = .normal

        overrides.elsewhere.surface = WhereStylesheet.MatteSurface(
            fill: .init(base: base.card.elsewherePaper.surface.fill.base, tintMix: 0),
            outline: outline,
            shadow: .init(color: shadow.color, radius: 8, offsetY: 3),
            pressedTintOpacity: 0.08,
        )
        overrides.welcome.surface = .matte(WhereStylesheet.MatteSurface(
            fill: paper,
            outline: outline,
            shadow: shadow,
            pressedTintOpacity: 0,
        ))
        overrides.welcome.close.surface = .matte(WhereStylesheet.MatteSurface(
            fill: paper,
            outline: outline,
            shadow: .init(color: shadow.color, radius: 5, offsetY: 3),
            pressedTintOpacity: 0.1,
        ))
        // WhereStylesheet.MatteSurface owns the complete elevation; omit the legacy outer shadows.
        overrides.welcome.glowOpacity = 0
        overrides.welcome.liftOpacity = 0
        overrides.welcome.close.glowOpacity = 0
        overrides.welcome.close.liftOpacity = 0
        overrides.privacy.surface = .matte(WhereStylesheet.MatteSurface(
            fill: .init(base: Color(red: 0.05, green: 0.125, blue: 0.25), tintMix: 0),
            outline: .init(
                opacity: increasedContrast ? 0.65 : base.privacyPassportCard.outlineOpacity,
                width: increasedContrast ? 1.5 : base.privacyPassportCard.outlineWidth,
            ),
            shadow: .init(color: shadow.color, radius: 6, offsetY: 3),
            pressedTintOpacity: 0,
        ))
        overrides.forecast.surfaceWashOpacity = 0
        overrides.forecast.summarySurface = .matte(WhereStylesheet.MatteSurface(
            fill: .init(base: base.locationForecast.summary.paper, tintMix: 0),
            outline: outline,
            shadow: .init(color: shadow.color, radius: 8, offsetY: 3),
            pressedTintOpacity: 0,
        ))
        overrides.forecast.summaryShadowOpacity = 0
        return overrides
    }
}
