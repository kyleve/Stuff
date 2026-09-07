import CoreGraphics
@testable import Flyover
import Testing

struct FlyoverCanvasZoomPlanTests {
    @Test func tallCanvasFillsAvailableWidthWithoutFittingItsHeight() {
        let plan = FlyoverCanvasZoomPlan(
            canvasSize: CGSize(width: 1200, height: 6000),
            availableSize: CGSize(width: 500, height: 800),
            edgeInset: FlyoverStylesheet.default.canvas.framingInset,
        )

        #expect(abs(plan.widthZoom - 0.39) < 0.0001)
        #expect(plan.allZoom == 0.15)
    }

    @Test func zoomNeverExceedsFullSize() {
        let plan = FlyoverCanvasZoomPlan(
            canvasSize: CGSize(width: 100, height: 100),
            availableSize: CGSize(width: 500, height: 800),
            edgeInset: FlyoverStylesheet.default.canvas.framingInset,
        )

        #expect(plan.widthZoom == 1)
        #expect(plan.allZoom == 1)
    }

    @Test func zoomNeverDropsBelowTheReadableMinimum() {
        let plan = FlyoverCanvasZoomPlan(
            canvasSize: CGSize(width: 10000, height: 10000),
            availableSize: CGSize(width: 500, height: 800),
            edgeInset: FlyoverStylesheet.default.canvas.framingInset,
        )

        #expect(plan.widthZoom == 0.15)
        #expect(plan.allZoom == 0.15)
    }

    @Test func zoomingPreservesTheCanvasPointAtTheViewportCenter() {
        let plan = FlyoverCanvasZoomPlan(
            canvasSize: CGSize(width: 2000, height: 2000),
            availableSize: CGSize(width: 400, height: 400),
            edgeInset: FlyoverStylesheet.default.canvas.framingInset,
        )
        let zoomedInOffset = plan.contentOffset(
            preservingViewportCenterIn: CGRect(x: 300, y: 500, width: 400, height: 400),
            from: 0.5,
            to: 1,
        )
        let zoomedOutOffset = plan.contentOffset(
            preservingViewportCenterIn: CGRect(
                origin: zoomedInOffset,
                size: CGSize(width: 400, height: 400),
            ),
            from: 1,
            to: 0.5,
        )

        #expect(zoomedInOffset == CGPoint(x: 800, y: 1200))
        #expect(zoomedOutOffset == CGPoint(x: 300, y: 500))
    }

    @Test func preservedCenterIsClampedToTheScrollableCanvas() {
        let plan = FlyoverCanvasZoomPlan(
            canvasSize: CGSize(width: 2000, height: 2000),
            availableSize: CGSize(width: 400, height: 400),
            edgeInset: FlyoverStylesheet.default.canvas.framingInset,
        )

        #expect(
            plan.contentOffset(
                preservingViewportCenterIn: CGRect(x: 0, y: 0, width: 400, height: 400),
                from: 1,
                to: 0.5,
            ) == .zero,
        )
        #expect(
            plan.contentOffset(
                preservingViewportCenterIn: CGRect(x: 1600, y: 1600, width: 400, height: 400),
                from: 1,
                to: 0.5,
            ) == CGPoint(x: 600, y: 600),
        )
    }
}
