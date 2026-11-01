import BroadwayUI
import SwiftUI

/// Applies the privacy card's finish without making its content observe motion.
struct PrivacyPassportCardSurface<Content: View>: View {
    let tilt: TiltProvider
    @ViewBuilder let content: Content
    var ambientShadowOverride: WhereStylesheet.MatteSurface.Shadow?
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        // Elevation responds to the surrounding page; the passport's paper, ink, and
        // artwork share one dark appearance inside this boundary.
        PrivacyPassportDarkSurface(
            tilt: tilt,
            ambientShadow: ambientShadowOverride ?? ambientShadow,
            content: content,
        )
        .foregroundStyle(Color(uiColor: .label))
        .environment(\.whereThemeSecondaryInk, nil)
        .environment(\.colorScheme, .dark)
        .bMode(.dark)
    }

    private var ambientShadow: WhereStylesheet.MatteSurface.Shadow? {
        if case let .matte(paper) = stylesheet.privacyPassportCard.surface { paper.shadow }
        else { nil }
    }
}

private struct PrivacyPassportDarkSurface<Content: View>: View {
    let tilt: TiltProvider
    let ambientShadow: WhereStylesheet.MatteSurface.Shadow?
    let content: Content

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.whereComponentStylesheet) private var components

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
                    printedContent.matteSurface(surface, tint: reflection.accent, in: shape)
            }
        }
        .overlay { WhereComponentArtwork(role: .privacy, plane: .exterior, shape: shape) }
        .tint(reflection.accent)
        .contentShape(shape)
    }

    private var surface: WhereStylesheet.SurfaceTreatment {
        var surface = stylesheet.privacyPassportCard.surface
        if case var .matte(paper) = surface, let ambientShadow {
            paper.shadow = ambientShadow
            surface = .matte(paper)
        }
        return surface
    }

    private var printedContent: some View {
        let style = stylesheet.privacyPassportCard
        let reflection = style.reflectiveSurface
        return content
            .modifier(WhereComponentTextStyle(role: .privacy))
            .background {
                ZStack {
                    if style.surface.usesReflection {
                        LinearGradient(
                            colors: [reflection.backgroundTop, reflection.backgroundBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing,
                        )
                    }
                    if let background = components[.privacy].background { background }
                    if components[.privacy].nativeArtwork.contains(.rosette) {
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
                    WhereComponentArtwork(
                        role: .privacy,
                        plane: .interior,
                        shape: RoundedRectangle(cornerRadius: style.cornerRadius),
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
