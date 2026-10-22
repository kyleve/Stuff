import CoreGraphics
@testable import SnapshotReviewUI
import Testing

struct ReviewCanvasGeometryTests {
    @Test func excludesMarginsAndNormalizesImagePoint() {
        let bounds = CGRect(x: 20, y: 40, width: 200, height: 400)
        #expect(ReviewCanvasGeometry.point(at: CGPoint(x: 0, y: 0), bounds: bounds) == nil)
        let center = ReviewCanvasGeometry.point(at: CGPoint(x: 120, y: 240), bounds: bounds)
        #expect(center?.x == 0.5)
        #expect(center?.y == 0.5)
        #expect(ReviewCanvasGeometry.point(at: .zero, bounds: .zero) == nil)
    }

    @Test func preservesRelativeScrollThroughChangedHeightAndClampsOverscroll() {
        let viewport = CGSize(width: 400, height: 800)
        let result = ReviewCanvasGeometry.offset(
            previous: CGPoint(x: 0, y: 1200),
            oldContent: CGSize(width: 400, height: 2000),
            newContent: CGSize(width: 400, height: 3000),
            viewport: viewport,
        )
        #expect(result.y == 2200)
        #expect(result.x == 0)
        let clamped = ReviewCanvasGeometry.offset(
            previous: CGPoint(x: -10, y: 5000),
            oldContent: CGSize(width: 800, height: 2000),
            newContent: CGSize(width: 300, height: 400),
            viewport: viewport,
        )
        #expect(clamped == .zero)
    }
}
