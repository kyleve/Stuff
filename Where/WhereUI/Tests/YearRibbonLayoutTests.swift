import CoreGraphics
import Testing
import WhereCore
@testable import WhereUI

struct YearRibbonLayoutTests {
    @Test func mapsEachDayToItsExactCalendarWidth() {
        let rect = YearRibbonLayout.segmentRect(
            day: CalendarDay(year: 2026, month: 2, day: 1),
            size: CGSize(width: 365, height: 18),
            lane: 0,
            laneCount: 1,
        )

        #expect(rect == CGRect(x: 31, y: 0, width: 1, height: 18))
    }

    @Test func leavesMissingDaysBetweenRecordedSegmentsUnpainted() {
        let size = CGSize(width: 365, height: 18)
        let beforeGap = YearRibbonLayout.segmentRect(
            day: CalendarDay(year: 2026, month: 1, day: 3),
            size: size,
            lane: 0,
            laneCount: 1,
        )
        let afterGap = YearRibbonLayout.segmentRect(
            day: CalendarDay(year: 2026, month: 1, day: 6),
            size: size,
            lane: 0,
            laneCount: 1,
        )

        #expect(afterGap.minX - beforeGap.maxX == 2)
    }

    @Test func dividesMultiRegionDaysIntoEqualLanes() {
        let rect = YearRibbonLayout.segmentRect(
            day: CalendarDay(year: 2024, month: 1, day: 1),
            size: CGSize(width: 366, height: 18),
            lane: 1,
            laneCount: 3,
        )

        #expect(rect == CGRect(x: 0, y: 6, width: 1, height: 6))
    }

    @Test func datesSkippedInCivilTimeKeepDistinctLogicalPositions() {
        let columns = (29 ... 31).map { day in
            YearRibbonLayout.segmentRect(
                day: CalendarDay(year: 2011, month: 12, day: day),
                size: CGSize(width: 365, height: 18),
                lane: 0,
                laneCount: 1,
            )
        }
        #expect(columns.map(\.minX) == [362, 363, 364])
        #expect(columns.map(\.width) == [1, 1, 1])
    }

    @Test func leapDayKeepsItsOwnColumn() {
        let column = YearRibbonLayout.segmentRect(
            day: CalendarDay(year: 2024, month: 2, day: 29),
            size: CGSize(width: 366, height: 18),
            lane: 0,
            laneCount: 1,
        )
        #expect(column == CGRect(x: 59, y: 0, width: 1, height: 18))
    }
}
