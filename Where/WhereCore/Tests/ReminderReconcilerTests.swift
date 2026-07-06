import Foundation
import Testing
@testable import WhereCore

/// Covers the reminder intent + badge/schedule reconciliation the controller
/// delegates every reminder call to.
struct ReminderReconcilerTests {
    private struct Harness {
        let reconciler: ReminderReconciler
        let store: SwiftDataStore
        let spy: SpyReminderScheduler
        let scanner: DataIssueScanner
    }

    private static func makeReconciler(
        now: @escaping @Sendable () -> Date,
    ) throws -> Harness {
        let store = try SwiftDataStore.inMemory()
        let aggregator = DayAggregator(
            calendar: WhereCoreTestSupport.calendar(),
            timeZone: WhereCoreTestSupport.pacific,
        )
        let reader = ReportReader(store: store, aggregator: aggregator, attributor: .shared)
        let scanner = DataIssueScanner(
            reportReader: reader,
            attributor: .shared,
            calendar: WhereCoreTestSupport.calendar(),
            now: now,
        )
        let spy = SpyReminderScheduler()
        let reconciler = ReminderReconciler(
            scheduler: spy,
            reportReader: reader,
            issueScanner: scanner,
            calendar: WhereCoreTestSupport.calendar(),
            now: now,
        )
        return Harness(reconciler: reconciler, store: store, spy: spy, scanner: scanner)
    }

    private static let noIssues = Double(DriftThreshold.default.rawValue)

    @Test func configureEnabledRequestsAuthorizationAndReconciles() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let h = try Self.makeReconciler(now: { now })
        await h.reconciler.configure(
            enabled: true,
            time: .defaultEvening,
            issueAlertsEnabled: false,
            driftThresholdMeters: Self.noIssues,
        )

        #expect(await h.spy.authorizationRequests == 1)
        #expect(await h.spy.reconcileCount == 1)
        #expect(await h.spy.lastEnabled == true)
        // An empty store this far into the year has a non-empty past backlog.
        #expect(await (h.spy.lastBadgeCount ?? 0) > 0)
    }

    @Test func configureDisabledClearsScheduleAndBadge() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let h = try Self.makeReconciler(now: { now })
        await h.reconciler.configure(
            enabled: false,
            time: .defaultEvening,
            issueAlertsEnabled: false,
            driftThresholdMeters: Self.noIssues,
        )

        #expect(await h.spy.authorizationRequests == 0)
        #expect(await h.spy.lastEnabled == false)
        #expect(await h.spy.lastBadgeCount == 0)
    }

    @Test func reconcileAfterIngestSkipsWhenTodayCoveredButForcesOnPastChange() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let h = try Self.makeReconciler(now: { now })
        try await h.store.perform {
            try await h.store.add(sample: LocationSample(
                timestamp: now,
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 0,
                source: .gpsSignificantChange,
            ))
        }
        await h.reconciler.configure(
            enabled: true,
            time: .defaultEvening,
            issueAlertsEnabled: false,
            driftThresholdMeters: Self.noIssues,
        )
        #expect(await h.spy.reconcileCount == 1)

        let today = WhereCoreTestSupport.calendar().startOfDay(for: now)
        // Today already covered + only today changed → no extra reconcile.
        await h.reconciler.reconcileAfterIngest(changedDays: [today])
        #expect(await h.spy.reconcileCount == 1)

        // A change on a different day forces a reconcile.
        let earlier = try #require(WhereCoreTestSupport.calendar().date(
            byAdding: .day,
            value: -3,
            to: today,
        ))
        await h.reconciler.reconcileAfterIngest(changedDays: [earlier])
        #expect(await h.spy.reconcileCount == 2)
    }

    /// Seed a primary region (a January California day) so the scanner reports a
    /// non-zero unresolved-issue count, then prove the badge is exactly the
    /// backlog plus that count when issue alerts are on — and just the backlog
    /// when they're off.
    @Test func badgeFoldsInIssueCountWhenIssueAlertsEnabled() async throws {
        let now = WhereCoreTestSupport.iso("2026-06-15T12:00:00-07:00")
        let h = try Self.makeReconciler(now: { now })
        try await h.store.perform {
            try await h.store.setManualDay(DayPresence(
                date: WhereCoreTestSupport.iso("2026-01-10T00:00:00-08:00"),
                regions: [.california],
            ))
        }
        let threshold = Double(DriftThreshold.default.rawValue)
        let issueCount = try await h.scanner.currentIssueCount(
            year: 2026,
            driftThresholdMeters: threshold,
            force: true,
        )
        #expect(issueCount > 0)

        await h.reconciler.configure(
            enabled: true,
            time: .defaultEvening,
            issueAlertsEnabled: false,
            driftThresholdMeters: threshold,
        )
        let backlogOnly = try #require(await h.spy.lastBadgeCount)

        await h.reconciler.configure(
            enabled: true,
            time: .defaultEvening,
            issueAlertsEnabled: true,
            driftThresholdMeters: threshold,
        )
        let combined = try #require(await h.spy.lastBadgeCount)

        #expect(combined == backlogOnly + issueCount)
    }

    /// With logging reminders off but issue alerts on, the badge still surfaces
    /// the issue count (and no per-day reminders are scheduled).
    @Test func badgeCarriesIssueCountWhenRemindersOffButAlertsOn() async throws {
        let now = WhereCoreTestSupport.iso("2026-06-15T12:00:00-07:00")
        let h = try Self.makeReconciler(now: { now })
        try await h.store.perform {
            try await h.store.setManualDay(DayPresence(
                date: WhereCoreTestSupport.iso("2026-01-10T00:00:00-08:00"),
                regions: [.california],
            ))
        }
        let threshold = Double(DriftThreshold.default.rawValue)
        let issueCount = try await h.scanner.currentIssueCount(
            year: 2026,
            driftThresholdMeters: threshold,
            force: true,
        )
        #expect(issueCount > 0)

        await h.reconciler.configure(
            enabled: false,
            time: .defaultEvening,
            issueAlertsEnabled: true,
            driftThresholdMeters: threshold,
        )

        #expect(await h.spy.lastEnabled == false)
        #expect(await h.spy.lastScheduleDays.isEmpty)
        #expect(await h.spy.lastBadgeCount == issueCount)
    }
}

private actor SpyReminderScheduler: LoggingReminderScheduling {
    private(set) var authorizationRequests = 0
    private(set) var reconcileCount = 0
    private(set) var lastBadgeCount: Int?
    private(set) var lastScheduleDays: [Date] = []
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
        scheduleDays: [Date],
        reminderTime _: ReminderTime,
        enabled: Bool,
    ) async {
        reconcileCount += 1
        lastBadgeCount = badgeCount
        lastScheduleDays = scheduleDays
        lastEnabled = enabled
    }
}
