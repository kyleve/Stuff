import SwiftUI

/// Applies the reflective privacy surface without making its content observe motion.
struct PrivacyPassportCardSurface<Content: View>: View {
    let tilt: TiltProvider
    @ViewBuilder let content: Content

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.privacyPassportCard
        let reflection = style.reflectiveSurface
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius)

        content
            .background {
                ZStack {
                    LinearGradient(
                        colors: [reflection.backgroundTop, reflection.backgroundBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing,
                    )
                    SecurityPrintRosette(
                        tint: reflection.accent,
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
                .regular.tint(reflection.accent.opacity(style.glassTintOpacity)),
                in: shape,
            )
            .tiltSheen(
                tilt: tilt,
                staticRoll: reflection.staticPose.roll,
                staticPitch: reflection.staticPose.pitch,
                in: shape,
                intensity: reflection.intensity,
                staticGlintIntensity: reflection.staticGlintIntensity,
            )
            .tint(reflection.accent)
            .environment(\.colorScheme, .dark)
            .clipShape(shape)
            .contentShape(shape)
            .shadow(
                color: reflection.backgroundTop.opacity(reflection.glowOpacity),
                radius: style.accentGlow.radius,
                y: style.accentGlow.offsetY,
            )
            .shadow(
                color: Color.black.opacity(style.liftShadow.opacity),
                radius: style.liftShadow.radius,
                y: style.liftShadow.offsetY,
            )
    }
}

#if DEBUG
    #Preview {
        PrivacyPassportCardSurface(tilt: .preview) {
            Text(LocalizedStringResource.settingsPrivacyTitle)
                .padding()
                .frame(maxWidth: .infinity)
        }
        .padding()
        .whereBroadwayRoot()
    }
#endif
