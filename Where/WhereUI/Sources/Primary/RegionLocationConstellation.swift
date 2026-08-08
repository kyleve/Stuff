import SwiftUI

/// Draws static, geographically placed GPS pinpricks with a soft halo, clipped
/// to the same region silhouette used by the card's security-print watermark.
struct RegionLocationConstellation: View {
    let path: Path
    let points: [RegionLocationConstellationLayout.Point]
    let tint: Color
    let artworkStyle: WhereStylesheet.CardStyle.RegionShape.Artwork
    let style: WhereStylesheet.CardStyles.Constellation

    var body: some View {
        Canvas { context, size in
            guard
                points.isEmpty == false,
                let transform = RegionArtworkTransform(
                    path: path,
                    size: size,
                    style: artworkStyle,
                )
            else { return }

            var projectedContext = context
            transform.apply(to: &projectedContext)
            projectedContext.clip(to: path)

            let coreRadius = style.coreDiameter / 2 / transform.scale
            let innerHaloRadius = style.haloRadius * 0.55 / transform.scale
            let outerHaloRadius = style.haloRadius / transform.scale
            let coreTint = tint.mix(with: .white, by: style.coreWhiteMix, in: .perceptual)

            for point in points {
                projectedContext.fill(
                    circle(center: point.position, radius: outerHaloRadius),
                    with: .color(tint.opacity(style.haloOpacity * 0.28)),
                )
                projectedContext.fill(
                    circle(center: point.position, radius: innerHaloRadius),
                    with: .color(tint.opacity(style.haloOpacity)),
                )
                projectedContext.fill(
                    circle(center: point.position, radius: coreRadius),
                    with: .color(coreTint.opacity(style.coreOpacity)),
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func circle(center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2,
        ))
    }
}

#if DEBUG
    #Preview {
        let path = Path { path in
            path.addRoundedRect(
                in: CGRect(x: 0, y: 0, width: 200, height: 100),
                cornerSize: CGSize(width: 18, height: 18),
            )
        }
        if let artwork = WhereStylesheet.default.card.regular.regionShape?.watermark {
            RegionLocationConstellation(
                path: path,
                points: [
                    .init(position: CGPoint(x: 40, y: 30), horizontalAccuracy: 8),
                    .init(position: CGPoint(x: 92, y: 64), horizontalAccuracy: 18),
                    .init(position: CGPoint(x: 158, y: 42), horizontalAccuracy: 32),
                ],
                tint: .orange,
                artworkStyle: artwork,
                style: .standard,
            )
            .frame(width: 320, height: 180)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 28))
            .padding()
        }
    }
#endif
