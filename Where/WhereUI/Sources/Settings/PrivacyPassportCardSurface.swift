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
        let printed = content.background { PrivacyPassportPrint(style: style) }

        Group {
            switch style.surface {
                case .reflective:
                    PrivacyPassportReflectiveSurface(
                        content: printed,
                        tilt: tilt,
                        style: style,
                        shape: shape,
                    )
                case .matte:
                    printed.matteSurface(style.surface, tint: reflection.accent, in: shape)
            }
        }
        .tint(reflection.accent)
        .environment(\.colorScheme, .dark)
        .bMode(.dark)
        .contentShape(shape)
    }
}

private struct PrivacyPassportPrint: View {
    let style: WhereStylesheet.PrivacyPassportCardStyle

    var body: some View {
        let reflection = style.reflectiveSurface
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

private struct PrivacyPassportReflectiveSurface<Content: View>: View {
    let content: Content
    let tilt: TiltProvider
    let style: WhereStylesheet.PrivacyPassportCardStyle
    let shape: RoundedRectangle

    var body: some View {
        let reflection = style.reflectiveSurface
        content
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
    }
}

#if DEBUG
    #Preview { PrivacyPassportCardSurfacePreview() }

    private struct PrivacyPassportCardSurfacePreview: View {
        var body: some View {
            PrivacyPassportCardSurface(tilt: .preview) {
                Text(LocalizedStringResource.settingsPrivacyTitle)
                    .padding()
                    .frame(maxWidth: .infinity)
            }
            .padding()
            .whereBroadwayRoot()
        }
    }
#endif
