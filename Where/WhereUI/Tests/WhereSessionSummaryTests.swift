import Foundation
import Testing
import WhereCore
import WhereTesting
import WhereUI

/// Covers that the session's launch / foreground lifecycle hooks actually drive
/// the daily-summary configuration down to the summary reconciler's scheduler.
@MainActor
struct WhereSessionSummaryTests {
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
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        return WhereSession(services: services, preferences: preferences)
    }

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
        let spy = SpyDailySummaryScheduler()
        let session = try makeSession(preferences: makePreferences(), scheduler: spy)
        // Disabling persists synchronously, so the launch hook sees it off and
        // never requests authorization.
        session.summaryEnabled = false

        await session.start()

        #expect(await spy.authorizationRequests == 0)
        #expect(await spy.lastEnabled == false)
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
