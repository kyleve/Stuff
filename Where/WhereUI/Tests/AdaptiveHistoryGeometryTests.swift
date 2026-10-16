import CoreGraphics
import Testing
@testable import WhereUI

struct AdaptiveHistoryGeometryTests {
    @Test func independentInsetsRetainTheContainersCoordinateSpace() {
        let geometry = AdaptiveHistoryGeometry(
            bounds: CGRect(x: 20, y: 30, width: 800, height: 600),
            insets: .init(top: 20, left: 50, bottom: 30, right: 80),
            regions: [],
            layoutDirection: .rightToLeft,
        )
        #expect(geometry.contentBounds == CGRect(x: 70, y: 50, width: 670, height: 550))
    }

    @Test func insetsNeverProduceNegativePaneDimensions() {
        var geometry = AdaptiveHistoryTestSupport.portrait
        geometry.bounds.size = CGSize(width: 20, height: 20)
        geometry.insets.left = 30
        #expect(geometry.contentBounds.width == 0)
        #expect(geometry.contentBounds.height == 0)
    }

    @Test func floatingControlsChooseTheirSideOfAnActiveHinge() {
        var geometry = AdaptiveHistoryTestSupport.portrait
        geometry.regions = [AdaptiveHistoryTestSupport.horizontalDivision]
        let lower = geometry.unobstructedBounds(near: CGPoint(x: 669, y: 917))
        #expect(lower.minY == 495.5)
        #expect(lower.maxY == 917)
        #expect(!lower.intersects(geometry.regions[0].frame))
        let upper = geometry.unobstructedBounds(near: CGPoint(x: 0, y: 82))
        #expect(upper.minY == 82)
        #expect(upper.maxY == 455.5)
    }

    @Test func floatingControlsAvoidAnActiveCameraWithoutMirroringRTL() {
        var geometry = AdaptiveHistoryTestSupport.portrait
        geometry.layoutDirection = .rightToLeft
        let camera = AdaptiveHistoryGeometry.Region(
            kind: .occlusion,
            frame: CGRect(x: 600, y: 820, width: 69, height: 97),
            isActive: true,
        )
        geometry.regions = [camera]
        let clear = geometry.unobstructedBounds(near: CGPoint(x: 669, y: 917))
        #expect(!clear.intersects(camera.frame))
        #expect(geometry.contentBounds.contains(clear))
        geometry.regions[0].isActive = false
        #expect(geometry.unobstructedBounds(near: CGPoint(x: 669, y: 917)) == geometry
            .contentBounds)
    }
}
