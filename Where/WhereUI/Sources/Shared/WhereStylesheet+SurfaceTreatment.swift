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

extension WhereStylesheet.LocationWelcomeStyle.Close {
    func buttonStyle(tint: Color) -> CardSurfaceButtonStyle<Circle> {
        CardSurfaceButtonStyle(surface: surface, tint: tint, shape: Circle())
    }
}
