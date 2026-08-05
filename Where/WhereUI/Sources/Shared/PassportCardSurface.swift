import SwiftUI

/// Applies either the security-print glass or reflective privacy surface to a
/// passport card without making the card's content observe device motion.
struct PassportCardSurface<Content: View>: View {
    let surface: PassportCardSurfaceKind
    let isInteractive: Bool
    let shape: RoundedRectangle
    @ViewBuilder let content: Content

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.colorScheme) private var colorScheme

    private var style: WhereStylesheet.PassportCardStyle {
        stylesheet.passportCard
    }

    private var surfaceTint: Color {
        surface.isReflective ? style.reflectiveSurface.accent : .accentColor
    }

    var body: some View {
        let reflection = style.reflectiveSurface
        content
            .background {
                ZStack {
                    if surface.isReflective {
                        LinearGradient(
                            colors: [reflection.backgroundTop, reflection.backgroundBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing,
                        )
                    }

                    SecurityPrintRosette(
                        tint: surfaceTint,
                        wobble: style.rosette.wobble,
                        lineWidth: style.rosette.lineWidth,
                        primaryRingSpacing: style.rosette.primaryRingSpacing,
                        secondaryRingSpacing: style.rosette.secondaryRingSpacing,
                        primaryOpacity: style.rosette.primaryOpacity,
                        secondaryOpacity: style.rosette.secondaryOpacity,
                    )
                }
            }
            .glassEffect(
                .regular.tint(surfaceTint.opacity(style.glassTintOpacity))
                    .interactive(isInteractive),
                in: shape,
            )
            .tiltSheen(
                tilt: surface.tilt,
                staticRoll: reflection.staticPose.roll,
                staticPitch: reflection.staticPose.pitch,
                in: shape,
                intensity: surface.isReflective ? reflection.intensity : 0,
                staticGlintIntensity: surface.isReflective
                    ? reflection.staticGlintIntensity
                    : 0,
            )
            .tint(surfaceTint)
            .environment(\.colorScheme, surface.isReflective ? .dark : colorScheme)
    }
}

#if DEBUG
    #Preview {
        PassportCardSurface(
            surface: .reflective(tilt: .preview),
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
