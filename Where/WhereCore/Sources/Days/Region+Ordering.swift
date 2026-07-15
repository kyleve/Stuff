import Foundation
import RegionKit

/// Day-count ranking of `Region`s. Lives in `WhereCore` — not `RegionKit` —
/// because it's about the app's presence/day-count domain, not region geometry
/// or lookup; `RegionKit` stays focused on regions and geofencing.
extension Region {
    /// Each region's position in the catalog's canonical order (`Region.allCases`
    /// = the manifest order, then `.other`). This is the app's canonical
    /// tiebreak: whenever two regions compare equal on some metric (most often an
    /// equal day count), comparisons fall back to it so rankings, widget rows,
    /// and calendar footers stay deterministic instead of riding on `Dictionary`
    /// iteration order. Precomputed once rather than scanning
    /// `allCases.firstIndex(of:)` per comparison.
    public static let declarationOrder: [Region: Int] = Dictionary(
        uniqueKeysWithValues: Region.allCases.enumerated().map { ($1, $0) },
    )

    /// `regions` in the catalog's canonical order — the same `declarationOrder`
    /// tiebreak used for ranking, but without a day-count metric. The catalog-
    /// driven way to display a *set* of regions in a stable order (e.g. the
    /// regions present on a calendar day), replacing `Region.allCases.filter`.
    public static func inCanonicalOrder(_ regions: some Sequence<Region>) -> [Region] {
        regions.sorted { declarationOrder[$0, default: 0] < declarationOrder[$1, default: 0] }
    }

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

    /// The "primary" regions for a year's `totals`: the top `count` regions by
    /// day count, with `.other` excluded (it's a catch-all bucket, never a
    /// headline place). The single definition of "primary", shared by the
    /// Primary/Elsewhere split (`RegionRanking`) and the headless data-issue scan
    /// that drives the badge and notification — so the count the badge shows
    /// can't disagree with what the Resolve tab would compute.
    public static func primaryRegions(in totals: [Region: Int], count: Int = 2) -> [Region] {
        rankedByDayCount(
            totals.filter { $0.value > 0 },
            days: { $0.value },
            region: { $0.key },
        )
        .map(\.key)
        .filter { $0 != .other }
        .prefix(max(0, count))
        .map(\.self)
    }
}
