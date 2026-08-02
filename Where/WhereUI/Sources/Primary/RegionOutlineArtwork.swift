import RegionKit
import SwiftUI

/// Projects RegionKit coordinates into the repeated silhouette artwork on a
/// regular region card, preserving geographic aspect and antimeridian-spanning
/// multipart regions.
struct RegionOutlineArtwork: View {
    enum Placement {
        case watermark
        case stamp
    }

    let outlines: [RegionOutline]
    let tint: Color
    let style: WhereStylesheet.CardStyle.RegionShape
    let placement: Placement

    var body: some View {
        Canvas { context, size in
            guard
                let box = BoundingBox.enclosing(outlines),
                let longitudeSpan = LongitudeSpan.enclosing(
                    outlines.lazy.flatMap { outline in
                        outline.coordinates.lazy.map(\.longitude)
                    },
                )
            else { return }

            let latitudeSpan = max(box.maxLatitude - box.minLatitude, 0.0001)
            let midLatitude = (box.minLatitude + box.maxLatitude) / 2
            let longitudeCorrection = max(cos(midLatitude * .pi / 180), 0.1)
            let projectedLongitudeSpan = max(
                longitudeSpan.degrees * longitudeCorrection,
                0.0001,
            )
            let layout = layout(in: size)
            let scale = min(
                layout.extent.width / projectedLongitudeSpan,
                layout.extent.height / latitudeSpan,
            )

            func point(for coordinate: Coordinate) -> CGPoint {
                let longitudeDelta = (coordinate.longitude - longitudeSpan.center + 540)
                    .truncatingRemainder(dividingBy: 360) - 180
                return CGPoint(
                    x: layout.center.x
                        + longitudeDelta * longitudeCorrection * scale * layout.scale,
                    y: layout.center.y
                        + (midLatitude - coordinate.latitude) * scale * layout.scale,
                )
            }

            for outline in outlines {
                guard let first = outline.coordinates.first else { continue }
                var path = Path()
                path.move(to: point(for: first))
                for coordinate in outline.coordinates.dropFirst() {
                    path.addLine(to: point(for: coordinate))
                }
                path.closeSubpath()

                switch placement {
                    case .watermark:
                        context.fill(
                            path,
                            with: .color(tint.opacity(style.watermarkFillOpacity)),
                        )
                        context.stroke(
                            path,
                            with: .color(tint.opacity(style.watermarkStrokeOpacity)),
                            lineWidth: style.watermarkStrokeWidth,
                        )
                    case .stamp:
                        context.fill(
                            path,
                            with: .color(tint.opacity(style.stampFillOpacity)),
                        )
                        context.stroke(path, with: .color(tint), lineWidth: style.stampStrokeWidth)
                }
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
        @State private var outlines: [RegionOutline] = []

        var body: some View {
            if let style = WhereStylesheet.default.card.regular.regionShape {
                RegionOutlineArtwork(
                    outlines: outlines,
                    tint: .orange,
                    style: style,
                    placement: .watermark,
                )
                .frame(width: 320, height: 180)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 28))
                .task {
                    outlines = await RegionGeometryCatalog.outlines(for: .california)
                }
            }
        }
    }
#endif
