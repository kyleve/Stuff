import SFSafeSymbols
import SwiftUI

/// A circular rubber-stamp impression — double ring, centered region glyph and
/// year, with the region name curved along the top arc — tilted as if an
/// official pressed it onto a passport page. The card stylesheet owns its
/// complete drawing treatment for both regular and compact cards.
struct EntryStamp: View {
    let title: String
    let year: Int
    let symbol: SFSymbol
    let tint: Color
    let style: WhereStylesheet.CardStyle.EntryStamp
    let regionPath: Path
    let regionShape: WhereStylesheet.CardStyle.RegionShape?

    var body: some View {
        let size = style.size
        ZStack {
            Circle()
                .strokeBorder(
                    tint.opacity(style.outerRing.opacity),
                    lineWidth: size * style.outerRing.lineWidthFraction,
                )
            Circle()
                .strokeBorder(
                    tint.opacity(style.innerRing.opacity),
                    style: StrokeStyle(
                        lineWidth: size * style.innerRing.lineWidthFraction,
                        dash: [
                            size * style.innerRing.dash.lengthFraction,
                            size * style.innerRing.dash.spacingFraction,
                        ],
                    ),
                )
                .padding(size * style.innerRing.insetFraction)

            VStack(spacing: size * style.content.spacingFraction) {
                if let regionShape, !regionPath.isEmpty {
                    RegionOutlineArtwork(
                        path: regionPath,
                        tint: tint,
                        style: regionShape.stamp,
                    )
                    .frame(
                        width: size * style.content.artworkExtent.width,
                        height: size * style.content.artworkExtent.height,
                    )
                } else {
                    Image(systemSymbol: symbol)
                        .font(style.content.symbolFont.font(for: size))
                }
                Text(verbatim: String(year))
                    .font(style.content.yearFont.font(for: size))
                    .monospacedDigit()
            }
            .foregroundStyle(tint.opacity(style.content.opacity))

            if let arc = style.arc {
                ArcText(
                    text: title,
                    size: size,
                    tint: tint,
                    style: arc,
                )
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(style.rotationDegrees))
        .accessibilityHidden(true)
    }
}

/// Lays out `text` along the upper arc of a circle of the given `radius`,
/// centered at twelve o'clock — the curved lettering of a rubber stamp. The
/// angular span grows with the character count (capped) so short and long
/// region names both stay legible.
private struct ArcText: View {
    let text: String
    let size: CGFloat
    let tint: Color
    let style: WhereStylesheet.CardStyle.EntryStamp.Arc

    var body: some View {
        let characters = Array(text)
        let sweep = min(
            style.maximumSweepDegrees,
            Double(characters.count) * style.sweepDegreesPerCharacter,
        )
        ZStack {
            ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .font(style.font.font(for: size))
                    .foregroundStyle(tint.opacity(style.opacity))
                    .offset(y: -size * style.radiusFraction)
                    .rotationEffect(angle(at: index, count: characters.count, sweep: sweep))
            }
        }
    }

    private func angle(at index: Int, count: Int, sweep: Double) -> Angle {
        guard count > 1 else { return .zero }
        let fraction = Double(index) / Double(count - 1) - 0.5
        return .degrees(fraction * sweep)
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
