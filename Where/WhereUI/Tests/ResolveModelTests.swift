import Foundation
import Testing
import WhereCore
import WhereTesting
@_spi(Testing) @testable import WhereUI

/// Covers `ResolveModel` — the Resolve tab's issue list and dismiss action.
@MainActor
struct ResolveModelTests {
    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(
            from: DateComponents(year: year, month: month, day: day, hour: 12),
        )!
    }

    @Test func loadPopulatesMissingDayIssues() async throws {
        let store = try TestStore()
        let now = date(year: 2026, month: 2, day: 10)
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            now: { now },
        )
        let resolve = ResolveModel(
            services: services,
            preferences: WherePreferences(store: InMemoryKeyValueStore()),
        )

        try await services.journal.addManualDay(
            date: date(year: 2026, month: 1, day: 1),
            regions: [.california],
        )
        await resolve.load(year: 2026, primaryRegions: [.california])

        #expect(!resolve.dataIssues.isEmpty)
        #expect(resolve.dataIssues.contains { $0.category == .missingDays })
    }

    @Test func dismissWritesToStoreAndRemovesRow() async throws {
        let store = try TestStore()
        let now = date(year: 2026, month: 6, day: 15)
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            now: { now },
        )
        let resolve = ResolveModel(
            services: services,
            preferences: WherePreferences(store: InMemoryKeyValueStore()),
        )

        // Two calendar-adjacent days with disjoint regions produce a real,
        // dismissible abrupt-change issue, so `dismiss` runs against an issue the
        // scanner actually returned from `load(...)` — no seeded fixture, no
        // `setDataIssues` short-circuit.
        try await services.journal.addManualDay(
            date: date(year: 2026, month: 3, day: 1),
            regions: [.california],
        )
        try await services.journal.addManualDay(
            date: date(year: 2026, month: 3, day: 2),
            regions: [.newYork],
        )
        await resolve.load(year: 2026, primaryRegions: [.california, .newYork])

        let issue = try #require(resolve.dataIssues.first { $0.isDismissible })
        await resolve.dismiss(issue)
        #expect(!resolve.dataIssues.contains { $0.id == issue.id })

        let keys = try await store.dismissedIssueKeys()
        #expect(keys.contains(issue.id.storageKey))
    }

    /// The empty-state guard: `hasLoaded` starts false and flips once the first
    /// scan lands, so `ResolutionView` can hold a spinner instead of flashing
    /// "all clear" under a non-zero badge.
    @Test func loadMarksTheModelLoaded() async throws {
        let store = try TestStore()
        let now = date(year: 2026, month: 2, day: 10)
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            now: { now },
        )
        let resolve = ResolveModel(
            services: services,
            preferences: WherePreferences(store: InMemoryKeyValueStore()),
        )

        #expect(!resolve.hasLoaded)
        await resolve.load(year: 2026, primaryRegions: [.california])
        #expect(resolve.hasLoaded)
    }

    /// Seeding a fixture also counts as loaded, so the seeded "empty" preview
    /// renders its empty state rather than a stuck spinner.
    @Test func seedingMarksTheModelLoaded() throws {
        let store = try TestStore()
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        let resolve = ResolveModel(
            services: services,
            preferences: WherePreferences(store: InMemoryKeyValueStore()),
        )

        resolve.setDataIssues([])
        #expect(resolve.hasLoaded)
    }
}
