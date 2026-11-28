import SFSafeSymbols
import SwiftUI

struct RegionCardSecurityPrint: View {
    let card: WhereStylesheet.CardStyle
    let cardStyles: WhereStylesheet.CardStyles
    let tint: Color
    let symbol: SFSymbol
    let regionPaths: RegionArtworkPaths?
    let showsRecordedPoints: Bool

    var body: some View {
        let rosette = card.rosette
        let rosetteFill = cardStyles.rosetteFill
        return ZStack {
            SecurityPrintRosette(
                tint: tint,
                wobble: rosette.wobble,
                lineWidth: rosette.lineWidth,
                primaryRingSpacing: rosette.primaryRingSpacing,
                secondaryRingSpacing: rosette.secondaryRingSpacing,
                primaryOpacity: rosetteFill.primary,
                secondaryOpacity: rosetteFill.secondary,
            )

            if
                let regionShape = card.regionShape,
                let regionPath = regionPaths?.microprint,
                !regionPath.isEmpty
            {
                RegionOutlineSecurityBorder(
                    paths: [regionPath],
                    tint: tint,
                    cornerRadius: card.cornerRadius,
                    inset: regionShape.securityBorder.inset,
                    glyphSize: regionShape.securityBorder.glyphSize,
                    spacing: regionShape.securityBorder.spacing,
                    opacity: regionShape.securityBorder.opacity,
                )
            }

            if
                let regionShape = card.regionShape,
                let regionPath = regionPaths?.watermark,
                !regionPath.isEmpty
            {
                RegionOutlineArtwork(
                    path: regionPath,
                    tint: tint,
                    style: regionShape.watermark,
                    constellationPoints: showsRecordedPoints
                        ? regionPaths?.constellation ?? []
                        : [],
                    constellationStyle: cardStyles.constellation,
                )
            } else {
                Image(systemSymbol: symbol)
                    .font(.system(size: card.watermarkFontSize))
                    .foregroundStyle(tint.opacity(cardStyles.watermarkOpacity))
                    .rotationEffect(.degrees(-14))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: card.watermarkOffset.width, y: card.watermarkOffset.height)
            }
        }
        .blendMode(card.paper == nil ? cardStyles.securityPrint.backgroundBlendMode : .normal)
        .clipShape(RoundedRectangle(cornerRadius: card.cornerRadius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview("Region card") {
        RegionSummaryCard(
            regionDays: RegionDays(region: .california, days: 148),
            caption: "Home base",
            year: 2026,
        )
        .whereBroadwayRoot()
    }
#endif
