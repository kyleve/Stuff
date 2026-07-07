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
    /// `declarationOrder`. The single home for the "most days first, stable
    /// order" ranking, so every surface that ranks regions (year reports,
    /// widgets, calendar footers, notifications) shares one rule that can't
    /// quietly drift between them.
    ///
    /// `Element` is whatever row the caller already has (a small day-count
    /// struct, a `[Region: Int]` entry, …); supply the two accessors and get the
    /// same collection back, sorted.
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
