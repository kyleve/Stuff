import RegionKit
import SwiftUI

/// Draws a cached, pre-projected region path with stylesheet-owned projection
/// geometry and ink treatment while preserving its geographic aspect.
struct RegionOutlineArtwork: View {
    let path: Path
    let tint: Color
    let style: WhereStylesheet.CardStyle.RegionShape.Artwork

    var body: some View {
        Canvas { context, size in
            let bounds = path.boundingRect
            guard !path.isEmpty, bounds.width > 0, bounds.height > 0 else { return }
            let scale = min(
                size.width * style.extent.width / bounds.width,
                size.height * style.extent.height / bounds.height,
            ) * style.scale
            var projectedContext = context
            projectedContext.translateBy(
                x: size.width * style.center.x,
                y: size.height * style.center.y,
            )
            projectedContext.scaleBy(x: scale, y: scale)
            projectedContext.translateBy(x: -bounds.midX, y: -bounds.midY)

            projectedContext.fill(
                path,
                with: .color(tint.opacity(style.fillOpacity)),
            )
            if let stroke = style.stroke {
                projectedContext.stroke(
                    path,
                    with: .color(tint.opacity(stroke.opacity)),
                    lineWidth: stroke.width / scale,
                )
            }
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
