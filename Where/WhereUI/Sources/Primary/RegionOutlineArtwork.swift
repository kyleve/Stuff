import RegionKit
import SwiftUI

/// Places a cached, pre-projected region path into the repeated silhouette
/// artwork on a regular card while preserving its geographic aspect.
struct RegionOutlineArtwork: View {
    enum Placement {
        case watermark
        case stamp
    }

    let path: Path
    let tint: Color
    let style: WhereStylesheet.CardStyle.RegionShape
    let placement: Placement

    var body: some View {
        Canvas { context, size in
            let bounds = path.boundingRect
            guard !path.isEmpty, bounds.width > 0, bounds.height > 0 else { return }
            let layout = layout(in: size)
            let scale = min(
                layout.extent.width / bounds.width,
                layout.extent.height / bounds.height,
            ) * layout.scale
            var projectedContext = context
            projectedContext.translateBy(x: layout.center.x, y: layout.center.y)
            projectedContext.scaleBy(x: scale, y: scale)
            projectedContext.translateBy(x: -bounds.midX, y: -bounds.midY)

            switch placement {
                case .watermark:
                    projectedContext.fill(
                        path,
                        with: .color(tint.opacity(style.watermarkFillOpacity)),
                    )
                    projectedContext.stroke(
                        path,
                        with: .color(tint.opacity(style.watermarkStrokeOpacity)),
                        lineWidth: style.watermarkStrokeWidth / scale,
                    )
                case .stamp:
                    projectedContext.fill(
                        path,
                        with: .color(tint.opacity(style.stampFillOpacity)),
                    )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func layout(in size: CGSize) -> (center: CGPoint, extent: CGSize, scale: CGFloat) {
        switch placement {
            case .watermark:
                (
                    CGPoint(
                        x: size.width * style.watermarkCenter.x,
                        y: size.height * style.watermarkCenter.y,
                    ),
                    CGSize(
                        width: size.width * style.watermarkExtent.width,
                        height: size.height * style.watermarkExtent.height,
                    ),
                    style.watermarkScale,
                )
            case .stamp:
                (
                    CGPoint(x: size.width * 0.5, y: size.height * 0.5),
                    CGSize(
                        width: size.width * style.stampExtent.width,
                        height: size.height * style.stampExtent.height,
                    ),
                    style.stampScale,
                )
        }
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
                    style: style,
                    placement: .watermark,
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
