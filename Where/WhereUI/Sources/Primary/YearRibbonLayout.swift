import CoreGraphics

/// Maps a calendar day and region lane to its exact proportional rectangle in
/// the year ribbon, preserving unrecorded days as visible gaps.
enum YearRibbonLayout {
    static func segmentRect(
        ordinal: Int,
        daysInYear: Int,
        size: CGSize,
        lane: Int,
        laneCount: Int,
    ) -> CGRect {
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
