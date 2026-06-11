import Foundation
import Testing
import WhereCore
import WhereUI

/// Covers that the model's launch / foreground lifecycle hooks actually drive
/// the daily-summary configuration down to the controller's scheduler.
@MainActor
struct WhereModelSummaryTests {
    private func ephemeralDefaults() -> UserDefaults {
        let suite = "test.WhereModelSummary.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeModel(
        defaults: UserDefaults,
        scheduler: SpyDailySummaryScheduler,
    ) throws -> WhereModel {
        let controller = try WhereController(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: scheduler,
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        return WhereModel(controller: controller, defaults: defaults)
    }

    @Test func startConfiguresDailySummary() async throws {
        let spy = SpyDailySummaryScheduler()
        let model = try makeModel(defaults: ephemeralDefaults(), scheduler: spy)

        await model.start()

        #expect(await spy.authorizationRequests >= 1)
        #expect(await spy.reconcileCount >= 1)
        #expect(await spy.lastEnabled == true)
    }

    @Test func appBecameActiveConfiguresDailySummary() async throws {
        let spy = SpyDailySummaryScheduler()
        let model = try makeModel(defaults: ephemeralDefaults(), scheduler: spy)

        await model.appBecameActive()

        #expect(await spy.reconcileCount >= 1)
        #expect(await spy.lastEnabled == true)
    }

    @Test func startWithSummaryDisabledReconcilesDisabled() async throws {
        let spy = SpyDailySummaryScheduler()
        let model = try makeModel(defaults: ephemeralDefaults(), scheduler: spy)
        // Disabling persists synchronously, so the launch hook sees it off and
        // never requests authorization.
        model.summaryEnabled = false

        await model.start()

        #expect(await spy.authorizationRequests == 0)
        #expect(await spy.lastEnabled == false)
    }
}

/// Records the calls the model funnels into the daily-summary scheduler so the
/// lifecycle wiring can be asserted without touching `UNUserNotificationCenter`.
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
