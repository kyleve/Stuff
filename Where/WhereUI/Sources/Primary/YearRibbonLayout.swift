import CoreGraphics
import Foundation
import WhereCore

/// Maps a calendar day and region lane to its exact proportional rectangle in
/// the year ribbon, preserving unrecorded days as visible gaps.
enum YearRibbonLayout {
    /// Resolve geometry in a fixed Gregorian calendar so a skipped civil date
    /// still occupies its own column in a logical recording year.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    static func segmentRect(
        day: CalendarDay,
        size: CGSize,
        lane: Int,
        laneCount: Int,
    ) -> CGRect {
        guard let ordinal = calendar.ordinality(
            of: .day,
            in: .year,
            for: day.startOfDay(in: calendar),
        ) else {
            assertionFailure("Gregorian calendar could not place \(day) in its year")
            return .zero
        }
        let daysInYear = calendar.dayCount(ofYear: day.year)
        let dayWidth = size.width / CGFloat(daysInYear)
        let laneHeight = size.height / CGFloat(laneCount)
        return CGRect(
            x: CGFloat(ordinal - 1) * dayWidth,
            y: CGFloat(lane) * laneHeight,
            width: dayWidth,
            height: laneHeight,
        )
    }
}
