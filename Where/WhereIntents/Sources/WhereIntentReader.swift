import Foundation
import RegionKit
import WhereCore

/// The read half of the App Intents layer: turns a `WhereServices` into the
/// answers the query intents speak. Pure orchestration over the existing
/// `reports` / `recentActivity` collaborators (and the published widget
/// snapshot) — no aggregation of its own — so it stays a thin, testable value
/// the intents delegate to.
struct WhereIntentReader {
    let services: WhereServices
    var calendar = Calendar.whereIntents
    var now: @Sendable () -> Date = { Date() }
    /// The published widget snapshot to use for the `todayRegions()` fast path.
    /// Defaults to reading the shared App Group file; tests inject a value (or
    /// `nil`) so the store fallback is exercised deterministically.
    var todaySnapshot: @Sendable () -> WidgetSnapshot? = {
        (try? WidgetSnapshotStore.shared())?.read()
    }

    /// Day count for `region` in `year` — the `YearReport.totals` entry, or 0
    /// when the region logged nothing.
    func dayCount(in region: Region, year: Int) async throws -> Int {
        try await services.reports.yearReport(for: year).totals[region] ?? 0
    }

    /// The regions a calendar day counts for, matched by start-of-day in the
    /// reader's calendar (the same calendar the report was aggregated in).
    func regions(on date: Date) async throws -> Set<Region> {
        let year = calendar.component(.year, from: date)
        let startOfDay = calendar.startOfDay(for: date)
        let report = try await services.reports.yearReport(for: year)
        return report.days
            .first { calendar.startOfDay(for: $0.date) == startOfDay }?
            .regions ?? []
    }

    /// Today's regions, preferring the app-published widget snapshot (no store
    /// read) when it still describes today, and falling back to the year
    /// report's today row otherwise.
    func todayRegions() async throws -> Set<Region> {
        let today = calendar.startOfDay(for: now())
        if let snapshot = todaySnapshot(), calendar.startOfDay(for: snapshot.day) == today {
            return snapshot.dayRegions
        }
        return try await regions(on: today)
    }

    /// The on-device recent-activity narrative for `window`. Rethrows the
    /// summarizer's typed `ActivitySummaryUnavailableError` so the intent can
    /// speak an actionable reason rather than a generic failure.
    func recentActivity(_ window: RecentActivityWindow) async throws -> RecentActivitySummary {
        try await services.recentActivity.summary(for: window)
    }
}
