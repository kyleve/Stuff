import SwiftUI

/// Keeps the production glass order intact and gives matte cards the same shape and hit area.
struct RegionCardSurface: ViewModifier {
    let card: WhereStylesheet.CardStyle
    let glassTintOpacity: Double
    let tint: Color
    let interactive: Bool
    let tilt: TiltProvider?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: card.cornerRadius, style: .continuous)
        switch card.surface {
            case .reflective:
                content
                    .glassEffect(
                        .regular.tint(tint.opacity(glassTintOpacity)).interactive(interactive),
                        in: shape,
                    )
                    .tiltSheen(
                        tilt: tilt,
                        staticRoll: card.sheen.staticPose.roll,
                        staticPitch: card.sheen.staticPose.pitch,
                        in: shape,
                        intensity: card.sheen.intensity,
                        staticGlintIntensity: card.sheen.staticGlintIntensity,
                    )
                    .clipShape(shape)
                    .contentShape(shape)
                    .shadow(color: tint.opacity(card.glow.opacity), radius: card.glow.radius)
                    .shadow(
                        color: tint.opacity(card.lift.opacity),
                        radius: card.lift.radius,
                        y: card.lift.offsetY,
                    )
            case .matte:
                content.matteSurface(card.surface, tint: tint, in: shape)
        }
    }
}
