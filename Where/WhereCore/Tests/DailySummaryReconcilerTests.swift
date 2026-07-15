import Foundation
import RegionKit
import Testing
@testable import WhereCore

/// Covers the daily-summary intent + recap reconciliation the controller
/// delegates `configureDailySummary` to.
struct DailySummaryReconcilerTests {
    private static func makeReconciler(
        now: @escaping @Sendable () -> Date,
    ) throws -> (DailySummaryReconciler, SwiftDataStore, SpyDailySummaryScheduler) {
        let store = try SwiftDataStore.inMemory()
        let aggregator = DayAggregator(
            calendar: WhereCoreTestSupport.calendar(),
            timeZone: WhereCoreTestSupport.pacific,
        )
        let reader = ReportReader(
            store: store,
            aggregator: aggregator,
            attributor: RegionAttributor.shared,
        )
        let spy = SpyDailySummaryScheduler()
        let reconciler = DailySummaryReconciler(
            scheduler: spy,
            reportReader: reader,
            calendar: WhereCoreTestSupport.calendar(),
            now: now,
        )
        return (reconciler, store, spy)
    }

    @Test func summaryBodyContainsNoFormatPlaceholders() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let (reconciler, store, spy) = try Self.makeReconciler(now: { now })
        try await store.perform {
            try await store.setManualDay(DayPresence(
                date: WhereCoreTestSupport.iso("2026-02-01T00:00:00-08:00"),
                in: WhereCoreTestSupport.calendar(),
                regions: [.california],
            ))
            try await store.setManualDay(DayPresence(
                date: WhereCoreTestSupport.iso("2026-02-02T00:00:00-08:00"),
                in: WhereCoreTestSupport.calendar(),
                regions: [.newYork],
            ))
        }
        await reconciler.configure(enabled: true, time: .defaultMorning)

        let body = try #require(await spy.lastBody)
        #expect(!body.contains("%"))
        #expect(body.contains("California"))
        #expect(body.contains("New York"))
    }

    @Test func configureEnabledRequestsAuthorizationAndBuildsABody() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let (reconciler, store, spy) = try Self.makeReconciler(now: { now })
        try await store.perform {
            try await store.setManualDay(DayPresence(
                date: WhereCoreTestSupport.iso("2026-02-01T00:00:00-08:00"),
                in: WhereCoreTestSupport.calendar(),
                regions: [.california],
            ))
        }
        await reconciler.configure(enabled: true, time: .defaultMorning)

        #expect(await spy.authorizationRequests == 1)
        #expect(await spy.lastEnabled == true)
        #expect(await spy.lastTime == .defaultMorning)
        #expect(await !(spy.lastBody ?? "").isEmpty)
    }

    @Test func configureDisabledClearsTheSummary() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let (reconciler, _, spy) = try Self.makeReconciler(now: { now })
        await reconciler.configure(enabled: false, time: .defaultMorning)

        #expect(await spy.authorizationRequests == 0)
        #expect(await spy.lastEnabled == false)
        #expect(await spy.lastBody == "")
    }
}

private actor SpyDailySummaryScheduler: DailySummaryScheduling {
    private(set) var authorizationRequests = 0
    private(set) var reconcileCount = 0
    private(set) var lastEnabled: Bool?
    private(set) var lastTime: ReminderTime?
    private(set) var lastBody: String?

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return true
    }

    func isAuthorized() async -> Bool {
        true
    }

    func reconcile(enabled: Bool, time: ReminderTime, body: String) async {
        reconcileCount += 1
        lastEnabled = enabled
        lastTime = time
        lastBody = body
    }
}
