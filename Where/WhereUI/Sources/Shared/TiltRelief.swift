import SwiftUI

/// Adds a raised-ink light and shade to content without making its parent
/// observe device motion. The lightweight modified subtree alone invalidates
/// as the shared tilt provider publishes new samples.
struct TiltRelief: ViewModifier {
    var tilt: TiltProvider?
    var staticRoll: Double
    var staticPitch: Double
    var tint: Color
    var style: WhereStylesheet.CardStyle.Sheen.NameRelief

    @MotionIsStatic private var motionIsStatic

    func body(content: Content) -> some View {
        let state = TiltEffectState(
            tilt: tilt,
            staticRoll: staticRoll,
            staticPitch: staticPitch,
            motionIsStatic: motionIsStatic,
        )
        let direction = state.lightDirection(travel: style.travel)
        content
            .foregroundStyle(
                tint
                    .shadow(.inner(
                        color: .white.opacity(style.highlightOpacity),
                        radius: style.blurRadius,
                        x: -direction.width * style.depth,
                        y: -direction.height * style.depth,
                    ))
                    .shadow(.inner(
                        color: .black.opacity(style.shadowOpacity),
                        radius: style.blurRadius,
                        x: direction.width * style.depth,
                        y: direction.height * style.depth,
                    )),
            )
            .compositingGroup()
            .shadow(
                color: .white.opacity(style.highlightOpacity),
                radius: style.blurRadius,
                x: -direction.width * style.depth,
                y: -direction.height * style.depth,
            )
            .shadow(
                color: .black.opacity(style.shadowOpacity),
                radius: style.blurRadius,
                x: direction.width * style.depth,
                y: direction.height * style.depth,
            )
    }
}

extension View {
    /// Render this content as tilt-reactive raised ink using the same authored
    /// fallback pose as the containing card's sheen.
    func tiltRelief(
        tilt: TiltProvider?,
        staticRoll: Double,
        staticPitch: Double,
        tint: Color,
        style: WhereStylesheet.CardStyle.Sheen.NameRelief,
    ) -> some View {
        modifier(TiltRelief(
            tilt: tilt,
            staticRoll: staticRoll,
            staticPitch: staticPitch,
            tint: tint,
            style: style,
        ))
    }
}

#if DEBUG
    #Preview {
        Text("California")
            .font(.system(size: 38, weight: .semibold, design: .serif))
            .foregroundStyle(.indigo)
            .tiltRelief(
                tilt: nil,
                staticRoll: 0.3,
                staticPitch: -0.2,
                tint: .indigo,
                style: WhereStylesheet.default.card.regular.sheen.nameRelief,
            )
            .padding()
            .background(.background)
    }
#endif
