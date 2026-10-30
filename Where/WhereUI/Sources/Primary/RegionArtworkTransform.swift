import SwiftUI

/// The shared Canvas transform that places a projected region path inside its
/// card artwork extent while preserving geographic aspect.
struct RegionArtworkTransform {
    let scale: CGFloat
    let translation: CGPoint

    init?(
        path: Path,
        size: CGSize,
        style: WhereStylesheet.CardStyle.RegionShape.Artwork,
    ) {
        let bounds = path.boundingRect
        guard path.isEmpty == false, bounds.width > 0, bounds.height > 0 else { return nil }
        scale = min(
            size.width * style.extent.width / bounds.width,
            size.height * style.extent.height / bounds.height,
        ) * style.scale
        // Zero-sized authored artwork and collapsed layout proposals have no drawable transform.
        guard scale.isFinite, scale > 0 else { return nil }
        translation = CGPoint(
            x: size.width * style.center.x / scale - bounds.midX,
            y: size.height * style.center.y / scale - bounds.midY,
        )
        guard translation.x.isFinite, translation.y.isFinite else { return nil }
    }

    func apply(to context: inout GraphicsContext) {
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: translation.x, y: translation.y)
    }
}
