import CoreGraphics
import Testing
@testable import WhereUI

struct YearRibbonLayoutTests {
    @Test func mapsEachDayToItsExactCalendarWidth() {
        let rect = YearRibbonLayout.segmentRect(
            ordinal: 32,
            daysInYear: 365,
            size: CGSize(width: 365, height: 18),
            lane: 0,
            laneCount: 1,
        )

        #expect(rect == CGRect(x: 31, y: 0, width: 1, height: 18))
    }

    @Test func leavesMissingDaysBetweenRecordedSegmentsUnpainted() {
        let size = CGSize(width: 365, height: 18)
        let beforeGap = YearRibbonLayout.segmentRect(
            ordinal: 3,
            daysInYear: 365,
            size: size,
            lane: 0,
            laneCount: 1,
        )
        let afterGap = YearRibbonLayout.segmentRect(
            ordinal: 6,
            daysInYear: 365,
            size: size,
            lane: 0,
            laneCount: 1,
        )

        #expect(afterGap.minX - beforeGap.maxX == 2)
    }

    @Test func dividesMultiRegionDaysIntoEqualLanes() {
        let rect = YearRibbonLayout.segmentRect(
            ordinal: 1,
            daysInYear: 366,
            size: CGSize(width: 366, height: 18),
            lane: 1,
            laneCount: 3,
        )

        #expect(rect == CGRect(x: 0, y: 6, width: 1, height: 6))
    }
}
