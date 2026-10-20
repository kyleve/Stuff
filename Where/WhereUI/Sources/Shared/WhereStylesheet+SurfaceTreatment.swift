import BroadwayCore
import SwiftUI

extension WhereStylesheet {
    /// Adjusts runtime region ink without relying on a material's contrast adaptation.
    struct TintAdjustment: Equatable {
        var color: Color
        var fraction: Double

        static let unchanged = Self(color: .clear, fraction: 0)

        func apply(to tint: Color) -> Color {
            guard fraction > 0 else { return tint }
            return tint.mix(with: color, by: fraction, in: .perceptual)
        }
    }

    /// A component keeps its existing glass/coated rendering or uses opaque ink and paper.
    enum SurfaceTreatment: Equatable {
        case reflective
        case matte(MatteSurface)

        var usesReflection: Bool {
            switch self {
                case .reflective: true
                case .matte: false
            }
        }
    }

    /// Opaque paper, a printed edge, and a neutral drop shadow. Tint is supplied
    /// by the component so user-selected region colors remain runtime inputs.
    struct MatteSurface: Equatable {
        var fill: Fill
        var outline: Outline
        var shadow: Shadow
        var pressedTintOpacity: Double

        struct Fill: Equatable {
            var base: Color
            var tintMix: Double

            func color(tint: Color) -> Color {
                base.mix(with: tint, by: tintMix, in: .perceptual)
            }
        }

        struct Outline: Equatable {
            var opacity: Double
            var width: CGFloat
        }

        struct Shadow: Equatable {
            var color: Color
            var radius: CGFloat
            var offsetY: CGFloat
        }
    }

    /// Apply the finish after trait slicing so contrast and transparency cannot
    /// restore a reflection or remove Flat's edge and depth cues.
    mutating func applyFlatAppearance(traits: BTraits) {
        let isDark = traits.mode == .dark
        let increasedContrast = traits.accessibility.isDarkerSystemColorsEnabled
        let outline = MatteSurface.Outline(
            opacity: increasedContrast ? 0.65 : (isDark ? 0.4 : 0.32),
            width: increasedContrast ? 1.5 : 1,
        )
        let paper = MatteSurface.Fill(
            base: isDark ? Color(white: 0.12) : .white,
            tintMix: 0,
        )
        let shadow = MatteSurface.Shadow(
            color: .black.opacity(isDark ? 0.3 : 0.14),
            radius: 10,
            offsetY: 4,
        )
        let regionSurface = MatteSurface(
            fill: .init(base: isDark ? .black : .white, tintMix: isDark ? 0.58 : 0.52),
            outline: outline,
            shadow: shadow,
            pressedTintOpacity: 0.1,
        )
        card.regular.surface = .matte(regionSurface)
        var compactSurface = regionSurface
        compactSurface.shadow.radius = 6
        compactSurface.shadow.offsetY = 3
        card.compact.surface = .matte(compactSurface)
        let contentTint = TintAdjustment(
            color: isDark ? .white : .black,
            fraction: increasedContrast ? 0.75 : 0.6,
        )
        card.regular.contentTint = contentTint
        card.compact.contentTint = contentTint
        card.constellation.haloOpacity = 0
        card.securityPrint.backgroundBlendMode = .normal

        elsewhereCard.surface.treatment = .matte(MatteSurface(
            fill: .init(base: elsewhereCard.surface.paper, tintMix: 0),
            outline: outline,
            shadow: .init(color: shadow.color, radius: 8, offsetY: 3),
            pressedTintOpacity: 0.08,
        ))
        locationWelcome.surface = .matte(MatteSurface(
            fill: paper,
            outline: outline,
            shadow: shadow,
            pressedTintOpacity: 0,
        ))
        locationWelcome.close.surface = .matte(MatteSurface(
            fill: paper,
            outline: outline,
            shadow: .init(color: shadow.color, radius: 5, offsetY: 3),
            pressedTintOpacity: 0.1,
        ))
        // MatteSurface owns the complete elevation; omit the legacy outer shadows.
        locationWelcome.glow.opacity = 0
        locationWelcome.lift.opacity = 0
        locationWelcome.close.glow.opacity = 0
        locationWelcome.close.lift.opacity = 0
        elsewhereCard.surface.shadowOpacity = 0
        privacyPassportCard.surface = .matte(MatteSurface(
            fill: .init(base: Color(red: 0.05, green: 0.125, blue: 0.25), tintMix: 0),
            outline: .init(
                opacity: increasedContrast ? 0.65 : privacyPassportCard.outlineOpacity,
                width: increasedContrast ? 1.5 : privacyPassportCard.outlineWidth,
            ),
            shadow: .init(color: shadow.color, radius: 6, offsetY: 3),
            pressedTintOpacity: 0,
        ))
        locationForecast.ink.surfaceWashOpacity = 0
    }
}

extension WhereStylesheet.CardStyle {
    func buttonStyle(tint: Color) -> CardSurfaceButtonStyle<RoundedRectangle> {
        CardSurfaceButtonStyle(
            surface: surface,
            tint: tint,
            shape: RoundedRectangle(cornerRadius: cornerRadius),
        )
    }

    /// The zoom source must carry the same elevation as its complete card.
    struct TransitionElevation {
        let glow: WhereStylesheet.MatteSurface.Shadow
        let lift: WhereStylesheet.MatteSurface.Shadow
    }

    func transitionElevation(tint: Color) -> TransitionElevation {
        switch surface {
            case .reflective:
                TransitionElevation(
                    glow: .init(color: tint.opacity(glow.opacity), radius: glow.radius, offsetY: 0),
                    lift: .init(
                        color: tint.opacity(lift.opacity),
                        radius: lift.radius,
                        offsetY: lift.offsetY,
                    ),
                )
            case let .matte(style):
                TransitionElevation(
                    glow: .init(color: .clear, radius: 0, offsetY: 0),
                    lift: style.shadow,
                )
        }
    }
}

extension WhereStylesheet.ElsewhereCardStyle {
    var buttonStyle: CardSurfaceButtonStyle<RoundedRectangle> {
        CardSurfaceButtonStyle(
            surface: surface.treatment,
            tint: surface.ink,
            shape: RoundedRectangle(cornerRadius: cornerRadius),
        )
    }
}

extension WhereStylesheet.LocationWelcomeStyle.Close {
    func buttonStyle(tint: Color) -> CardSurfaceButtonStyle<Circle> {
        CardSurfaceButtonStyle(surface: surface, tint: tint, shape: Circle())
    }
}
