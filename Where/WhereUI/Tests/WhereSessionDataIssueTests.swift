import Foundation
import Testing
import WhereCore
import WhereTesting
@_spi(Testing) @testable import WhereUI

@MainActor
struct WhereSessionDataIssueTests {
    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(
            from: DateComponents(year: year, month: month, day: day, hour: 12),
        )!
    }

    @Test func refreshDataIssues_populatesMissingDays() async throws {
        let store = try TestStore()
        let now = date(year: 2026, month: 2, day: 10)
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            now: { now },
        )
        let session = WhereSession(services: services, selectedYear: 2026, now: { now })

        try await services.journal.addManualDay(
            date: date(year: 2026, month: 1, day: 1),
            regions: [.california],
        )
        await session.refresh()
        await session.refreshDataIssues(force: true)

        #expect(session.dataIssueCount > 0)
        #expect(session.dataIssues.contains { $0.category == .missingDays })
    }

    @Test func dismiss_writesToStoreAndRemovesRow() async throws {
        let store = try TestStore()
        let now = date(year: 2026, month: 2, day: 10)
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            now: { now },
        )
        let session = WhereSession(services: services, selectedYear: 2026, now: { now })

        let issue = BorderDriftIssue(
            day: DayPresence(date: date(year: 2026, month: 3, day: 1), regions: [.other]),
            nearestRegion: .california,
            distanceMeters: 1000,
        )
        session.setDataIssues([issue])
        #expect(session.dataIssueCount == 1)

        await session.dismiss(issue)
        #expect(!session.dataIssues.contains { $0.id == issue.id })

        let keys = try await store.dismissedIssueKeys()
        #expect(keys.contains(issue.id.storageKey))
    }

    @Test func driftThresholdChangePersists() throws {
        let store = try TestStore()
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let session = WhereSession(
            services: services,
            selectedYear: 2026,
            preferences: preferences,
        )

        session.driftThreshold = .km25
        #expect(preferences.driftThresholdMeters == DriftThreshold.km25.rawValue)
    }
}
