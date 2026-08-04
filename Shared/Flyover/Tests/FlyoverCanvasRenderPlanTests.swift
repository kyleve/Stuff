import CoreGraphics
@testable import Flyover
import Testing

struct FlyoverCanvasRenderPlanTests {
    @Test func visibleScreensNearestTheViewportCenterAreLive() {
        let frames = Dictionary(
            uniqueKeysWithValues: (0 ..< 6).map { index in
                (
                    index,
                    CGRect(x: CGFloat(index * 200), y: 0, width: 100, height: 100),
                )
            },
        )
        let plan = FlyoverCanvasRenderPlan(
            zoom: 1,
            visibleRect: CGRect(x: 350, y: 0, width: 400, height: 200),
            screenFrames: frames,
        )

        #expect(plan.liveScreenIDs == [2, 3])
    }

    @Test func liveScreensNeverExceedTheResidentLimit() {
        let frames = Dictionary(
            uniqueKeysWithValues: (0 ..< 10).map { index in
                (
                    index,
                    CGRect(x: CGFloat(index * 100), y: 0, width: 100, height: 100),
                )
            },
        )
        let plan = FlyoverCanvasRenderPlan(
            zoom: 1,
            visibleRect: CGRect(x: 0, y: 0, width: 1000, height: 200),
            screenFrames: frames,
        )

        #expect(FlyoverCanvasRenderPlan<Int>.maximumLiveScreenCount == 6)
        #expect(plan.liveScreenIDs.count == 6)
    }

    @Test func panningChangesTheLiveScreens() {
        let frames = Dictionary(
            uniqueKeysWithValues: (0 ..< 6).map { index in
                (
                    index,
                    CGRect(x: CGFloat(index * 200), y: 0, width: 100, height: 100),
                )
            },
        )
        let leftPlan = FlyoverCanvasRenderPlan(
            zoom: 1,
            visibleRect: CGRect(x: 0, y: 0, width: 300, height: 200),
            screenFrames: frames,
        )
        let rightPlan = FlyoverCanvasRenderPlan(
            zoom: 1,
            visibleRect: CGRect(x: 750, y: 0, width: 300, height: 200),
            screenFrames: frames,
        )

        #expect(leftPlan.liveScreenIDs == [0, 1])
        #expect(rightPlan.liveScreenIDs == [4, 5])
    }

    @Test func emptyViewportDoesNotLoadBeforeTheCanvasAppears() {
        let plan = FlyoverCanvasRenderPlan(
            zoom: 1,
            visibleRect: CGRect.zero,
            screenFrames: [0: CGRect(x: 0, y: 0, width: 100, height: 100)],
        )

        #expect(plan.liveScreenIDs.isEmpty)
    }

    @Test func displayRegionIncludesPlaceholderOverscan() {
        let plan = FlyoverCanvasRenderPlan<Int>(
            zoom: 1,
            visibleRect: CGRect(x: 0, y: 0, width: 300, height: 600),
            screenFrames: [:],
        )

        #expect(plan.shouldDisplay(CGRect(x: 650, y: 0, width: 100, height: 100)))
        #expect(plan.shouldDisplay(CGRect(x: 750, y: 0, width: 100, height: 100)) == false)
    }
}
