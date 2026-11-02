import BroadwayCore
import SwiftUI
import WhereCore

/// Sparse, resolved component overrides. Nil inherits the trait-adjusted base;
/// concrete values, including zero, replace only the named field.
struct WhereThemeOverrides: Equatable {
    var card = Card()
    var elsewhere = Elsewhere()
    var welcome = Welcome()
    var privacy = Privacy()
    var forecast = Forecast()
    var onboarding = Onboarding()

    struct Onboarding: Equatable {
        var usesOpaqueSurfaces: Bool?
    }

    struct Card: Equatable {
        var regular = Variant()
        var compact = Variant()
        var haloOpacity: Double?
        var backgroundBlendMode: BlendMode?

        struct Variant: Equatable {
            var surface: WhereStylesheet.SurfaceTreatment?
            var contentTint: WhereStylesheet.TintAdjustment?
        }
    }

    struct Elsewhere: Equatable {
        var surface: WhereStylesheet.MatteSurface?
    }

    struct Welcome: Equatable {
        var surface: WhereStylesheet.SurfaceTreatment?
        var glowOpacity: Double?
        var liftOpacity: Double?
        var close = Close()

        struct Close: Equatable {
            var surface: WhereStylesheet.SurfaceTreatment?
            var glowOpacity: Double?
            var liftOpacity: Double?
        }
    }

    struct Privacy: Equatable {
        var surface: WhereStylesheet.SurfaceTreatment?
    }

    struct Forecast: Equatable {
        var surfaceWashOpacity: Double?
        var summarySurface: WhereStylesheet.SurfaceTreatment?
        var summaryShadowOpacity: Double?
    }

    static func resolve(
        theme: WhereTheme,
        traits: BTraits,
        base: WhereStylesheet,
    ) -> Self {
        switch theme {
            case .standard: Self()
            case .alternate: WhereFlatTheme.overrides(traits: traits, base: base)
        }
    }

    /// Applies values only; theme selection and trait decisions belong to resolution.
    func apply(to sheet: inout WhereStylesheet) {
        if let value = onboarding.usesOpaqueSurfaces {
            sheet.onboarding.usesOpaqueSurfaces = value
        }
        if let value = card.regular.surface {
            sheet.card.regular.surface = value
        }
        if let value = card.regular.contentTint {
            sheet.card.regular.contentTint = value
        }
        if let value = card.compact.surface {
            sheet.card.compact.surface = value
        }
        if let value = card.compact.contentTint {
            sheet.card.compact.contentTint = value
        }
        if let value = card.haloOpacity {
            sheet.card.constellation.haloOpacity = value
        }
        if let value = card.backgroundBlendMode {
            sheet.card.securityPrint.backgroundBlendMode = value
        }
        if let value = elsewhere.surface {
            sheet.card.elsewherePaper.surface = value
        }
        if let value = welcome.surface {
            sheet.locationWelcome.surface = value
        }
        if let value = welcome.glowOpacity {
            sheet.locationWelcome.glow.opacity = value
        }
        if let value = welcome.liftOpacity {
            sheet.locationWelcome.lift.opacity = value
        }
        if let value = welcome.close.surface {
            sheet.locationWelcome.close.surface = value
        }
        if let value = welcome.close.glowOpacity {
            sheet.locationWelcome.close.glow.opacity = value
        }
        if let value = welcome.close.liftOpacity {
            sheet.locationWelcome.close.lift.opacity = value
        }
        if let value = privacy.surface {
            sheet.privacyPassportCard.surface = value
        }
        if let value = forecast.surfaceWashOpacity {
            sheet.locationForecast.ink.surfaceWashOpacity = value
        }
        if let value = forecast.summarySurface {
            sheet.locationForecast.summary.treatment = value
        }
        if let value = forecast.summaryShadowOpacity {
            sheet.locationForecast.summary.shadowOpacity = value
        }
    }
}
