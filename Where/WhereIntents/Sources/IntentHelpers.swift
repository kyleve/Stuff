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

/// Time an intent's work as one span named for `intent`, budgeted by
/// `IntentName.budget`.
///
/// Wraps the WhereCore read/write a `perform()` delegates to — not the whole
/// `perform()`: the `IntentServices.current()` wait is spanned separately (a
/// cold-start park is not a slow intent), and building the dialog and snippet
/// view from the result is free. `isolation` is forwarded so a `@MainActor`
/// `perform()` measures without hopping actors.
func measureIntent<R>(
    _ intent: WhereIntentsLog.IntentName,
    isolation: isolated (any Actor)? = #isolation,
    _ body: () async throws -> R,
) async rethrows -> R {
    try await WhereIntentsLog.logger.measure(
        .perform(intent),
        budget: intent.budget,
        isolation: isolation,
        body,
    )
}
