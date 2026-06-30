import Foundation

extension Region {
    /// Each region's position in `Region.allCases`. This declaration order is
    /// the app's canonical tiebreak: whenever two regions compare equal on some
    /// metric (most often an equal day count), comparisons fall back to it so
    /// rankings, widget rows, and calendar footers stay deterministic instead of
    /// riding on `Dictionary` iteration order. Precomputed once rather than
    /// scanning `allCases.firstIndex(of:)` per comparison.
    public static let declarationOrder: [Region: Int] = Dictionary(
        uniqueKeysWithValues: Region.allCases.enumerated().map { ($1, $0) },
    )

    /// Order `elements` by their day count, descending, breaking ties by
    /// `declarationOrder`. The single home for the app's "most days first, stable
    /// order" ranking — shared by the year ranking and Primary tab
    /// (`RegionRanking`), the widgets, the calendar month footers
    /// (`PresenceCalendar`), and the daily-summary notification — so the rule
    /// can't quietly drift between them.
    ///
    /// `Element` is whatever row the caller already has (a `RegionDays`, a
    /// `RegionDayTally`, a `[Region: Int]` entry, …); supply the two accessors
    /// and get the same collection back, sorted.
    public static func rankedByDayCount<Element>(
        _ elements: some Sequence<Element>,
        days: (Element) -> Int,
        region: (Element) -> Region,
    ) -> [Element] {
        elements.sorted { lhs, rhs in
            let lhsDays = days(lhs)
            let rhsDays = days(rhs)
            if lhsDays != rhsDays {
                return lhsDays > rhsDays
            }
            let lhsOrder = declarationOrder[region(lhs), default: 0]
            let rhsOrder = declarationOrder[region(rhs), default: 0]
            return lhsOrder < rhsOrder
        }
    }
}
