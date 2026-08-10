import SwiftUI

/// Presses content into its surface with paired inset light and shade plus a
/// restrained exterior edge. The lightweight modified subtree alone observes
/// device motion, so its parent does not invalidate for every sensor sample.
struct TiltRelief: ViewModifier {
    var tilt: TiltProvider?
    var staticRoll: Double
    var staticPitch: Double
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
        let insetOffset = CGSize(
            width: direction.width * style.depth,
            height: direction.height * style.depth,
        )
        let exteriorOffset = CGSize(
            width: direction.width * style.exteriorDepth,
            height: direction.height * style.exteriorDepth,
        )
        content
            .overlay {
                TiltInsetShadow(
                    subject: content,
                    highlightColor: .white.opacity(style.highlightOpacity),
                    shadowColor: .black.opacity(style.shadowOpacity),
                    radius: style.blurRadius,
                    highlightOffset: insetOffset,
                    shadowOffset: CGSize(width: -insetOffset.width, height: -insetOffset.height),
                )
            }
            .compositingGroup()
            .shadow(
                color: .white.opacity(style.highlightOpacity * style.exteriorOpacity),
                radius: style.exteriorBlurRadius,
                x: exteriorOffset.width,
                y: exteriorOffset.height,
            )
            .shadow(
                color: .black.opacity(style.shadowOpacity * style.exteriorOpacity),
                radius: style.exteriorBlurRadius,
                x: -exteriorOffset.width,
                y: -exteriorOffset.height,
            )
    }
}

extension View {
    /// Render this content as tilt-reactive pressed ink using the same authored
    /// fallback pose as the containing card's sheen.
    func tiltRelief(
        tilt: TiltProvider?,
        staticRoll: Double,
        staticPitch: Double,
        style: WhereStylesheet.CardStyle.Sheen.NameRelief,
    ) -> some View {
        modifier(TiltRelief(
            tilt: tilt,
            staticRoll: staticRoll,
            staticPitch: staticPitch,
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
                style: WhereStylesheet.default.card.regular.sheen.nameRelief,
            )
            .padding()
            .background(.background)
    }
#endif
