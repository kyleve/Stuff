import SwiftUI

/// Applies either the security-print glass or reflective privacy surface to a
/// passport card without making the card's content observe device motion.
struct PassportCardSurface<Content: View>: View {
    let tilt: TiltProvider?
    let isInteractive: Bool
    let shape: RoundedRectangle
    @ViewBuilder let content: Content

    @Environment(\.stylesheet) private var stylesheet

    private var style: WhereStylesheet.PassportCardStyle {
        stylesheet.passportCard
    }

    var body: some View {
        if let tilt {
            let reflection = style.reflectiveSurface
            content
                .background(reflection.background, in: shape)
                .tiltSheen(
                    tilt: tilt,
                    staticRoll: reflection.staticPose.roll,
                    staticPitch: reflection.staticPose.pitch,
                    in: shape,
                    intensity: reflection.intensity,
                    staticGlintIntensity: reflection.staticGlintIntensity,
                )
                .environment(\.colorScheme, .light)
        } else {
            content
                .background {
                    SecurityPrintRosette(
                        tint: .accentColor,
                        wobble: style.rosette.wobble,
                        lineWidth: style.rosette.lineWidth,
                        primaryRingSpacing: style.rosette.primaryRingSpacing,
                        secondaryRingSpacing: style.rosette.secondaryRingSpacing,
                        primaryOpacity: style.rosette.primaryOpacity,
                        secondaryOpacity: style.rosette.secondaryOpacity,
                    )
                }
                .glassEffect(
                    .regular.tint(Color.accentColor.opacity(style.glassTintOpacity))
                        .interactive(isInteractive),
                    in: shape,
                )
        }
    }
}

#if DEBUG
    #Preview {
        PassportCardSurface(
            tilt: .preview,
            isInteractive: false,
            shape: RoundedRectangle(
                cornerRadius: WhereStylesheet.default.passportCard.cornerRadius,
            ),
        ) {
            Text("Reflective passport surface")
                .padding()
                .frame(maxWidth: .infinity)
        }
        .padding()
        .whereBroadwayRoot()
    }
#endif
