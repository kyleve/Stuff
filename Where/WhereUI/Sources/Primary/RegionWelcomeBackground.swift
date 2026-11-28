import SwiftUI

struct RegionWelcomeBackground: View {
    let welcome: WhereStylesheet.LocationWelcomeStyle
    let tint: Color
    let microprint: Path?
    let watermark: Path?
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: welcome.cornerRadius)
        ZStack {
            if welcome.surface.usesReflection {
                shape.fill(.clear)
                    .glassEffect(
                        .regular.tint(tint.opacity(welcome.glassTintOpacity)),
                        in: shape,
                    )

                shape.fill(.background)
                    .opacity(welcome.paperOpacity)
            }

            ZStack {
                SecurityPrintRosette(
                    tint: tint,
                    wobble: stylesheet.card.regular.rosette.wobble,
                    lineWidth: stylesheet.card.regular.rosette.lineWidth,
                    primaryRingSpacing: stylesheet.card.regular.rosette.primaryRingSpacing,
                    secondaryRingSpacing: stylesheet.card.regular.rosette.secondaryRingSpacing,
                    primaryOpacity: stylesheet.card.rosetteFill.primary,
                    secondaryOpacity: stylesheet.card.rosetteFill.secondary,
                )

                if
                    let regionShape = stylesheet.card.regular.regionShape,
                    let microprint,
                    !microprint.isEmpty
                {
                    RegionOutlineSecurityBorder(
                        paths: [microprint],
                        tint: tint,
                        cornerRadius: welcome.cornerRadius,
                        inset: regionShape.securityBorder.inset,
                        glyphSize: regionShape.securityBorder.glyphSize,
                        spacing: regionShape.securityBorder.spacing,
                        opacity: regionShape.securityBorder.opacity,
                    )
                }

                if
                    let artwork = stylesheet.card.regular.regionShape,
                    let watermark,
                    !watermark.isEmpty
                {
                    RegionOutlineArtwork(
                        path: watermark,
                        tint: tint,
                        style: artwork.watermark,
                    )
                }
            }
            .blendMode(stylesheet.card.securityPrint.backgroundBlendMode)
        }
        .clipShape(shape)
        .allowsHitTesting(false)
    }
}

#if DEBUG
    #Preview("Welcome") {
        RegionWelcomeCard(
            presentation: .init(region: .newYork, greeting: .returnVisit),
            dismissAction: {},
            planStayAction: { _ in },
        )
        .whereBroadwayRoot()
    }
#endif
