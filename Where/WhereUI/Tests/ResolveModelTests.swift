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

        let issue = BorderDriftIssue(
            day: DayPresence(date: date(year: 2026, month: 3, day: 1), regions: [.other]),
            nearestRegion: .california,
            distanceMeters: 1000,
        )
        resolve.setDataIssues([issue])
        #expect(resolve.dataIssues.count == 1)

        await resolve.dismiss(issue)
        #expect(!resolve.dataIssues.contains { $0.id == issue.id })

        let keys = try await store.dismissedIssueKeys()
        #expect(keys.contains(issue.id.storageKey))
    }
}
