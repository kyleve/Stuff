import CoreGraphics
import SnapshotReviewCore

/// Converts only image-space hits and preserves progress through differently sized scroll extents.
enum ReviewCanvasGeometry {
    static func point(at location: CGPoint, bounds: CGRect) -> ReviewAnnotation.Point? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let point = ReviewAnnotation.Point(
            x: (location.x - bounds.minX) / bounds.width,
            y: (location.y - bounds.minY) / bounds.height,
        )
        return point.isValid ? point : nil
    }

    static func offset(
        previous: CGPoint,
        oldContent: CGSize,
        newContent: CGSize,
        viewport: CGSize,
    ) -> CGPoint {
        func axis(_ position: CGFloat, old: CGFloat, new: CGFloat, viewport: CGFloat) -> CGFloat {
            let fraction = min(1, max(0, position / max(1, old - viewport)))
            return fraction * max(0, new - viewport)
        }
        return CGPoint(
            x: axis(
                previous.x,
                old: oldContent.width,
                new: newContent.width,
                viewport: viewport.width,
            ),
            y: axis(
                previous.y,
                old: oldContent.height,
                new: newContent.height,
                viewport: viewport.height,
            ),
        )
    }
}
