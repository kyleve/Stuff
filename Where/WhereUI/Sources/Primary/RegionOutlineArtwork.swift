import RegionKit
import SwiftUI

/// Draws a cached, pre-projected region path with stylesheet-owned projection
/// geometry and ink treatment while preserving its geographic aspect.
struct RegionOutlineArtwork: View {
    let path: Path
    let tint: Color
    let style: WhereStylesheet.CardStyle.RegionShape.Artwork
    var constellationPoints: [RegionLocationConstellationLayout.Point] = []
    var constellationStyle = WhereStylesheet.CardStyles.Constellation.standard

    var body: some View {
        Canvas { context, size in
            guard let transform = RegionArtworkTransform(
                path: path,
                size: size,
                style: style,
            ) else {
                return
            }
            var projectedContext = context
            transform.apply(to: &projectedContext)

            projectedContext.fill(
                path,
                with: .color(tint.opacity(style.fillOpacity)),
            )
            if let stroke = style.stroke {
                projectedContext.stroke(
                    path,
                    with: .color(tint.opacity(stroke.opacity)),
                    lineWidth: stroke.width / transform.scale,
                )
            }
        }
        .overlay {
            RegionLocationConstellation(
                path: path,
                points: constellationPoints,
                tint: tint,
                artworkStyle: style,
                style: constellationStyle,
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview {
        RegionOutlineArtworkPreview()
            .padding()
    }

    private struct RegionOutlineArtworkPreview: View {
        @State private var path = Path()
        private let cache = RegionOutlinePathCache()

        var body: some View {
            if let style = WhereStylesheet.default.card.regular.regionShape {
                RegionOutlineArtwork(
                    path: path,
                    tint: .orange,
                    style: style.watermark,
                )
                .frame(width: 320, height: 180)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 28))
                .task {
                    path = await cache.path(for: .california, resolution: .medium)
                }
            }
        }
    }
#endif
