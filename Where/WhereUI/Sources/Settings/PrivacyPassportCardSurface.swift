import BroadwayUI
import SwiftUI

/// Applies the privacy card's finish without making its content observe motion.
struct PrivacyPassportCardSurface<Content: View>: View {
    let tilt: TiltProvider
    @ViewBuilder let content: Content

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.privacyPassportCard
        let reflection = style.reflectiveSurface
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius)

        Group {
            switch style.surface {
                case .reflective:
                    printedContent
                        .tiltSheen(
                            tilt: tilt,
                            staticRoll: reflection.staticPose.roll,
                            staticPitch: reflection.staticPose.pitch,
                            in: shape,
                            intensity: reflection.intensity,
                            staticGlintIntensity: reflection.staticGlintIntensity,
                        )
                        .clipShape(shape)
                        .overlay {
                            shape.strokeBorder(
                                reflection.accent.opacity(style.outlineOpacity),
                                lineWidth: style.outlineWidth,
                            )
                        }
                case .matte:
                    printedContent.matteSurface(style.surface, tint: reflection.accent, in: shape)
            }
        }
        .tint(reflection.accent)
        .environment(\.colorScheme, .dark)
        .bMode(.dark)
        .contentShape(shape)
    }

    private var printedContent: some View {
        let style = stylesheet.privacyPassportCard
        let reflection = style.reflectiveSurface
        return content
            .background {
                ZStack {
                    if style.surface.usesReflection {
                        LinearGradient(
                            colors: [reflection.backgroundTop, reflection.backgroundBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing,
                        )
                    }
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
