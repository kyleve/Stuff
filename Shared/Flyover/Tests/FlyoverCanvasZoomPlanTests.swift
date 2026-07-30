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
}
