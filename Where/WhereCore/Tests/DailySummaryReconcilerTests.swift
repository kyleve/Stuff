import Foundation
import Testing
@testable import WhereCore

/// Covers the daily-summary intent + recap reconciliation the controller
/// delegates `configureDailySummary` to.
struct DailySummaryReconcilerTests {
    private static let pacific = TimeZone(identifier: "America/Los_Angeles")!

    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        return calendar
    }

    private static func makeReconciler(
        now: @escaping @Sendable () -> Date,
    ) throws -> (DailySummaryReconciler, SwiftDataStore, SpyDailySummaryScheduler) {
        let store = try SwiftDataStore.inMemory()
        let aggregator = DayAggregator(calendar: calendar(), timeZone: pacific)
        let reader = ReportReader(store: store, aggregator: aggregator, attributor: .shared)
        let spy = SpyDailySummaryScheduler()
        let reconciler = DailySummaryReconciler(
            scheduler: spy,
            reportReader: reader,
            calendar: calendar(),
            now: now,
        )
        return (reconciler, store, spy)
    }

    @Test func configureEnabledRequestsAuthorizationAndBuildsABody() async throws {
        let now = iso("2026-03-15T12:00:00-07:00")
        let (reconciler, store, spy) = try Self.makeReconciler(now: { now })
        try await store.perform {
            try await store.setManualDay(DayPresence(
                date: iso("2026-02-01T00:00:00-08:00"),
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
        let now = iso("2026-03-15T12:00:00-07:00")
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

private func iso(_ string: String) -> Date {
    ISO8601DateFormatter().date(from: string) ?? Date(timeIntervalSince1970: 0)
}
