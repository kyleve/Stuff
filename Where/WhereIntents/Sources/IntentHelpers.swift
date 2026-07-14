import Foundation
import RegionKit
import WhereCore

/// The regions in the catalog's canonical order, so multi-region output
/// (entities and dialog) is stable regardless of set iteration order.
func orderedRegions(_ regions: Set<Region>) -> [Region] {
    Region.inCanonicalOrder(regions)
}

/// Whether "now" falls in `year`. Gates the day-count snippet's "Log today
/// here" button: logging today can only change the *current* year's count, so
/// on a card scoped to a past year the button would appear to do nothing.
func isCurrentYear(_ year: Int, now: Date = Date(), calendar: Calendar = .whereIntents) -> Bool {
    calendar.component(.year, from: now) == year
}
