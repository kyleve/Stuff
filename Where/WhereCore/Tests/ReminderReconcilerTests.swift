import Foundation
import RegionKit
import Testing
@testable import WhereCore

/// Covers the reminder intent + badge/schedule reconciliation the controller
/// delegates every reminder call to.
struct ReminderReconcilerTests {
    private static func makeReconciler(
        now: @escaping @Sendable () -> Date,
    ) throws -> (ReminderReconciler, SwiftDataStore, SpyReminderScheduler) {
        let store = try SwiftDataStore.inMemory()
        let aggregator = DayAggregator(
            calendar: WhereCoreTestSupport.calendar(),
            timeZone: WhereCoreTestSupport.pacific,
        )
        let reader = ReportReader(store: store, aggregator: aggregator, attributor: .shared)
        let spy = SpyReminderScheduler()
        let reconciler = ReminderReconciler(
            scheduler: spy,
            reportReader: reader,
            calendar: WhereCoreTestSupport.calendar(),
            now: now,
        )
        return (reconciler, store, spy)
    }

    @Test func configureEnabledRequestsAuthorizationAndReconciles() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let (reconciler, _, spy) = try Self.makeReconciler(now: { now })
        await reconciler.configure(enabled: true, time: .defaultEvening)

        #expect(await spy.authorizationRequests == 1)
        #expect(await spy.reconcileCount == 1)
        #expect(await spy.lastEnabled == true)
        // An empty store this far into the year has a non-empty past backlog.
        #expect(await (spy.lastBadgeCount ?? 0) > 0)
    }

    @Test func configureDisabledClearsScheduleAndBadge() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let (reconciler, _, spy) = try Self.makeReconciler(now: { now })
        await reconciler.configure(enabled: false, time: .defaultEvening)

        #expect(await spy.authorizationRequests == 0)
        #expect(await spy.lastEnabled == false)
        #expect(await spy.lastBadgeCount == 0)
    }

    @Test func reconcileAfterIngestSkipsWhenTodayCoveredButForcesOnPastChange() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let (reconciler, store, spy) = try Self.makeReconciler(now: { now })
        try await store.perform {
            try await store.add(sample: LocationSample(
                timestamp: now,
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 0,
                source: .gpsSignificantChange,
            ))
        }
        await reconciler.configure(enabled: true, time: .defaultEvening)
        #expect(await spy.reconcileCount == 1)

        let today = WhereCoreTestSupport.calendar().startOfDay(for: now)
        // Today already covered + only today changed → no extra reconcile.
        await reconciler.reconcileAfterIngest(changedDays: [today])
        #expect(await spy.reconcileCount == 1)

        // A change on a different day forces a reconcile.
        let earlier = try #require(WhereCoreTestSupport.calendar().date(
            byAdding: .day,
            value: -3,
            to: today,
        ))
        await reconciler.reconcileAfterIngest(changedDays: [earlier])
        #expect(await spy.reconcileCount == 2)
    }
}

private actor SpyReminderScheduler: LoggingReminderScheduling {
    private(set) var authorizationRequests = 0
    private(set) var reconcileCount = 0
    private(set) var lastBadgeCount: Int?
    private(set) var lastEnabled: Bool?

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return true
    }

    func isAuthorized() async -> Bool {
        true
    }

    func reconcile(
        badgeCount: Int,
        scheduleDays _: [Date],
        reminderTime _: ReminderTime,
        enabled: Bool,
    ) async {
        reconcileCount += 1
        lastBadgeCount = badgeCount
        lastEnabled = enabled
    }
}
