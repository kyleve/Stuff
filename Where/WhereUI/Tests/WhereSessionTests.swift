import Foundation
import Testing
import WhereCore
import WhereTesting
import WhereUI

/// Covers the always-on coordinator's launch / foreground lifecycle hooks: that
/// `start()` and `appBecameActive()` drive the persisted daily-summary intent
/// down to the reconciler's scheduler, and republish the widget snapshot from
/// whatever is already on disk. Tracking / authorization lives in
/// `WhereSessionTrackingTests`.
@MainActor
struct WhereSessionTests {
    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(
            from: DateComponents(year: year, month: month, day: day, hour: 12),
        )!
    }

    private func makePreferences() -> WherePreferences {
        WherePreferences(store: InMemoryKeyValueStore())
    }

    private func makeSession(
        preferences: WherePreferences,
        scheduler: SpyDailySummaryScheduler,
    ) throws -> WhereSession {
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: scheduler,
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        return WhereSession(services: services, preferences: preferences)
    }

    // MARK: - Daily-summary configuration

    @Test func startConfiguresDailySummary() async throws {
        let spy = SpyDailySummaryScheduler()
        let session = try makeSession(preferences: makePreferences(), scheduler: spy)

        await session.start()

        #expect(await spy.authorizationRequests >= 1)
        #expect(await spy.reconcileCount >= 1)
        #expect(await spy.lastEnabled == true)
    }

    @Test func appBecameActiveConfiguresDailySummary() async throws {
        let spy = SpyDailySummaryScheduler()
        let session = try makeSession(preferences: makePreferences(), scheduler: spy)

        await session.appBecameActive()

        #expect(await spy.reconcileCount >= 1)
        #expect(await spy.lastEnabled == true)
    }

    @Test func startWithSummaryDisabledReconcilesDisabled() async throws {
        let preferences = makePreferences()
        // The coordinator reads the persisted intent directly; disabling it in
        // preferences (what `RemindersSettingsModel` writes) means the launch
        // hook sees it off and never requests authorization.
        preferences.summaryEnabled = false
        let spy = SpyDailySummaryScheduler()
        let session = try makeSession(preferences: preferences, scheduler: spy)

        await session.start()

        #expect(await spy.authorizationRequests == 0)
        #expect(await spy.lastEnabled == false)
    }

    // MARK: - Widget snapshot republishing on launch / activation

    /// The widget extension only reads the published snapshot file, so opening
    /// the app with data already on disk must republish — otherwise the widget
    /// stays blank/stale until the next write.
    @Test func startPublishesWidgetSnapshotFromExistingData() async throws {
        let (session, refresher) = try await makePublishingSession()
        await session.start()
        #expect(await refresher.publishCount == 1)
        #expect(await refresher.lastSnapshot?.totals == [.california: 1])
    }

    /// Returning to the foreground (e.g. on a new calendar day) recomputes and
    /// republishes too.
    @Test func appBecameActiveRepublishesWidgetSnapshot() async throws {
        let (session, refresher) = try await makePublishingSession()
        await session.appBecameActive()
        #expect(await refresher.publishCount == 1)
        #expect(await refresher.lastSnapshot?.totals == [.california: 1])
    }

    /// A session whose services already hold one California day (seeded
    /// straight into the store so nothing is published yet), wired to a spy
    /// refresher and a fixed "now" so the year report is deterministic.
    private func makePublishingSession() async throws -> (WhereSession, SpyWidgetRefresher) {
        let store = try TestStore()
        // Seed straight into the store (inside `perform`, as the store
        // requires) so nothing is published before the session's lifecycle hook.
        let seed = DayPresence(date: date(year: 2026, month: 3, day: 1), regions: [.california])
        try await store.perform { try await store.setManualDay(seed) }
        let refresher = SpyWidgetRefresher()
        let now = date(year: 2026, month: 3, day: 15)
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: refresher,
            now: { now },
        )
        return (WhereSession(services: services), refresher)
    }
}

/// Records the calls the session funnels into the daily-summary scheduler so
/// the lifecycle wiring can be asserted without touching
/// `UNUserNotificationCenter`.
private actor SpyDailySummaryScheduler: DailySummaryScheduling {
    private(set) var authorizationRequests = 0
    private(set) var reconcileCount = 0
    private(set) var lastEnabled: Bool?
    private(set) var lastBody: String?

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return true
    }

    func isAuthorized() async -> Bool {
        true
    }

    func reconcile(enabled: Bool, time _: ReminderTime, body: String) async {
        reconcileCount += 1
        lastEnabled = enabled
        lastBody = body
    }
}

/// Captures the snapshots published through the widget publisher so the
/// session's launch/activation hooks can be checked for republishing widget
/// data.
private actor SpyWidgetRefresher: WidgetTimelineRefreshing {
    private(set) var publishedSnapshots: [WidgetSnapshot] = []

    var publishCount: Int {
        publishedSnapshots.count
    }

    var lastSnapshot: WidgetSnapshot? {
        publishedSnapshots.last
    }

    func publish(_ snapshot: WidgetSnapshot) async {
        publishedSnapshots.append(snapshot)
    }
}
