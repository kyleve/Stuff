import SwiftUI
import Testing
@testable import WhereUI

struct RegionLocationConstellationLayoutTests {
    @Test func keepsTheMostAccurateFixInEachVisualCell() {
        let path = Path { $0.addRect(CGRect(x: 0, y: 0, width: 100, height: 100)) }
        let coarse = RegionLocationConstellationLayout.Point(
            position: CGPoint(x: 10, y: 10),
            horizontalAccuracy: 100,
        )
        let precise = RegionLocationConstellationLayout.Point(
            position: CGPoint(x: 11, y: 11),
            horizontalAccuracy: 10,
        )
        let otherCell = RegionLocationConstellationLayout.Point(
            position: CGPoint(x: 80, y: 80),
            horizontalAccuracy: 30,
        )

        let selected = RegionLocationConstellationLayout.selectedPoints(
            from: [coarse, precise, otherCell],
            inside: path,
            gridResolution: 4,
            maximumCount: 10,
        )

        #expect(selected.count == 2)
        #expect(selected.contains(precise))
        #expect(selected.contains(coarse) == false)
        #expect(selected.contains(otherCell))
    }

    @Test func clipsOutsidePointsAndCapsTheMostSampledCellsDeterministically() {
        let path = Path { $0.addRect(CGRect(x: 0, y: 0, width: 100, height: 100)) }
        let dense = RegionLocationConstellationLayout.Point(
            position: CGPoint(x: 10, y: 10),
            horizontalAccuracy: 10,
        )
        let sparse = RegionLocationConstellationLayout.Point(
            position: CGPoint(x: 80, y: 80),
            horizontalAccuracy: 10,
        )
        let outside = RegionLocationConstellationLayout.Point(
            position: CGPoint(x: 120, y: 50),
            horizontalAccuracy: 1,
        )

        let selected = RegionLocationConstellationLayout.selectedPoints(
            from: [dense, dense, sparse, outside],
            inside: path,
            gridResolution: 4,
            maximumCount: 1,
        )

        #expect(selected == [dense])
    }
}
