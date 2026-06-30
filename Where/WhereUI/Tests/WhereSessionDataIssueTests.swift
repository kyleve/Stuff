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

    /// Live GPS ingestion writes into the store out-of-band of any session
    /// intent method, so the session must re-pull both its report and its
    /// data-issue scan off the data-change stream — otherwise the Resolve tab
    /// (and Primary) would show stale state until the next foreground/edit.
    @Test func liveIngestRefreshesReportAndDataIssues() async throws {
        let store = try TestStore()
        let now = date(year: 2026, month: 6, day: 15)
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let services = WhereServices(
            store: store,
            locationSource: source,
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            now: { now },
        )
        let session = WhereSession(services: services, selectedYear: 2026, now: { now })

        // Empty store: the backlog is one contiguous missing-days range and the
        // report has zero days. `start()` also wires the data-change observer.
        await session.start()
        try await waitUntil { session.dataIssueCount == 1 }
        #expect(session.trackedDayCount == 0)

        // A GPS sample lands inside that range. The observer must re-pull: the
        // day becomes present (splitting the range in two) and the report grows.
        await services.ingestor.start()
        source.emit(LocationSample(
            timestamp: date(year: 2026, month: 1, day: 15),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        ))

        try await waitUntil { session.trackedDayCount == 1 && session.dataIssueCount == 2 }

        await services.ingestor.stop()
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

private struct WaitTimeout: Error {}

/// Polls `predicate` on the main actor until it holds or the timeout elapses,
/// yielding between checks so the session's observer task can run.
@MainActor
private func waitUntil(
    timeout: Duration = .seconds(5),
    _ predicate: () -> Bool,
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !predicate() {
        if ContinuousClock.now >= deadline { throw WaitTimeout() }
        try await Task.sleep(for: .milliseconds(5))
    }
}
