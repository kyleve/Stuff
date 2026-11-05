import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

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
        existingStore: SwiftDataStore? = nil,
        readStore: (any WhereStore)? = nil,
        policy: DataCompatibilityPolicy = .foundation,
    ) throws -> Harness {
        let store = try existingStore ?? SwiftDataStore.inMemory()
        let reads = readStore ?? store
        let aggregator = DayAggregator(
            calendar: WhereCoreTestSupport.calendar(),
            timeZone: WhereCoreTestSupport.pacific,
        )
        let reader = ReportReader(
            store: reads,
            aggregator: aggregator,
            attributor: RegionAttributor.shared,
            history: LocationHistoryReader(
                store: reads,
                policy: policy,
                geography: HistoryRegionAttribution(),
            ),
        )
        let scanner = DataIssueScanner(
            reportReader: reader,
            attributor: RegionAttributor.shared,
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

    @Test func permissionCompletionAppliesAChangedTimeWithoutRestoringOldSettings() async throws {
        let now = WhereCoreTestSupport.iso("2026-06-15T12:00:00-07:00")
        let h = try Self.makeReconciler(now: { now })
        let gate = CompatibilityTestGate()
        await h.spy.holdAuthorization(at: gate)
        let pending = Task {
            await h.reconciler.configure(
                enabled: true,
                time: .defaultEvening,
                issueAlertsEnabled: true,
                driftThresholdMeters: Self.noIssues,
                requestAuthorization: true,
            )
        }
        await gate.waitUntilEntered()
        let changedTime = ReminderTime(hour: 19, minute: 30)
        await h.reconciler.configure(
            enabled: false,
            time: changedTime,
            issueAlertsEnabled: true,
            driftThresholdMeters: Self.noIssues,
            requestAuthorization: false,
        )
        #expect(await h.spy.reconcileCount == 1)
        await gate.resume()
        await pending.value
        #expect(await h.spy.reconcileCount == 2)
        #expect(await h.spy.lastTime == changedTime)
        #expect(await h.spy.lastReminders
            .allSatisfy { !$0.remindsToLogDay && $0.missingDayCount == 0 })
    }

    @Test func permissionCompletionStillReconcilesAfterAnInterveningRefresh() async throws {
        let now = WhereCoreTestSupport.iso("2026-06-15T12:00:00-07:00")
        let h = try Self.makeReconciler(now: { now })
        let gate = CompatibilityTestGate()
        await h.spy.holdAuthorization(at: gate)
        let pending = Task {
            await h.reconciler.configure(
                enabled: true,
                time: .defaultEvening,
                issueAlertsEnabled: false,
                driftThresholdMeters: Self.noIssues,
                requestAuthorization: true,
            )
        }
        await gate.waitUntilEntered()
        await h.reconciler.reconcile()
        #expect(await h.spy.reconcileCount == 1)
        await gate.resume()
        await pending.value
        #expect(await h.spy.reconcileCount == 2)
        #expect(await h.spy.lastEnabled == true)
    }

    @Test func disablingLoggingAfterReadFailureCancelsScheduleWithoutInventingAnIssueCount(
    ) async throws {
        let now = WhereCoreTestSupport.iso("2026-06-15T12:00:00-07:00")
        let store = try SwiftDataStore.inMemory()
        let access = DataCompatibilityAccess(
            base: store,
            requiredMajor: 0,
            policy: .foundation,
            onFailure: { _, _ in },
        )
        let h = try Self.makeReconciler(now: { now }, existingStore: store, readStore: access.store)
        await h.reconciler.configure(
            enabled: true,
            time: .defaultEvening,
            issueAlertsEnabled: true,
            driftThresholdMeters: Self.noIssues,
            requestAuthorization: true,
        )
        let previousBadge = try #require(await h.spy.lastBadgeCount)
        #expect(previousBadge > 0)
        #expect(await h.spy.lastScheduleDays.isEmpty == false)
        access.revoke()
        await h.scanner.invalidate()
        await h.reconciler.configure(
            enabled: false,
            time: .defaultEvening,
            issueAlertsEnabled: true,
            driftThresholdMeters: Self.noIssues,
            requestAuthorization: false,
        )
        #expect(await h.spy.lastScheduleDays.isEmpty)
        #expect(await h.spy.lastEnabled == false)
        #expect(await h.spy.lastBadgeCount == previousBadge)
        #expect(await h.spy.reconcileCount == 1)
    }

    @Test func badgeIncludesOneContinuousRecordingConcernAcrossOldYears() async throws {
        let now = WhereCoreTestSupport.iso("2002-01-01T12:00:00-08:00")
        let store = try await RecordingChoiceTestSupport.store()
        try await LocationHistoryReaderTestSupport.add(
            HistoricalDataIssueTestSupport.conflicts(at: [-600, 0, 600]),
            to: store,
        )
        let h = try Self.makeReconciler(
            now: { now },
            existingStore: store,
            policy: RecordingChoiceTestSupport.policy,
        )
        let scan = try await h.scanner.historicalScan(
            driftThresholdMeters: Self.noIssues,
            force: false,
        )
        #expect(scan.recording.issues.count == 1)
        #expect(scan.years.map(\.context.historicalYear) == [2000, 2001, 2002])
        await h.reconciler.configure(
            enabled: false,
            time: .defaultEvening,
            issueAlertsEnabled: true,
            driftThresholdMeters: Self.noIssues,
            requestAuthorization: true,
        )
        #expect(await h.spy.lastBadgeCount == scan.issues.count + 1)
    }

    @Test func oldIssuesRemainInBadgeAtYearRollover() async throws {
        let now = WhereCoreTestSupport.iso("2027-01-01T12:00:00-08:00")
        let h = try Self.makeReconciler(now: { now })
        try await h.store.perform {
            try await h.store.setManualDay(DayPresence(
                date: WhereCoreTestSupport.iso("2026-01-10T00:00:00-08:00"),
                in: WhereCoreTestSupport.calendar(),
                regions: [.california],
            ))
        }
        await h.reconciler.configure(
            enabled: false,
            time: .defaultEvening,
            issueAlertsEnabled: true,
            driftThresholdMeters: Self.noIssues,
            requestAuthorization: true,
        )
        #expect(await h.spy.lastBadgeCount == 2)
        #expect(await h.spy.authorizationRequests == 1)
    }

    @Test func disablingWhileHistoricalReadIsHeldCannotRestoreOldBadge() async throws {
        let now = WhereCoreTestSupport.iso("2026-06-15T12:00:00-07:00")
        let h = try Self.makeReconciler(now: { now })
        let gate = CompatibilityTestGate()
        await h.scanner.setBeforeHistoricalPublicationForTesting { await gate.suspend() }
        let pending = Task {
            await h.reconciler.configure(
                enabled: true,
                time: .defaultEvening,
                issueAlertsEnabled: true,
                driftThresholdMeters: Self.noIssues,
                requestAuthorization: true,
            )
        }
        await gate.waitUntilEntered()
        await h.reconciler.configure(
            enabled: false,
            time: .defaultEvening,
            issueAlertsEnabled: false,
            driftThresholdMeters: Self.noIssues,
            requestAuthorization: true,
        )
        await gate.resume()
        await pending.value
        #expect(await h.spy.reconcileCount == 1)
        #expect(await h.spy.lastBadgeCount == 0)
        #expect(await h.spy.lastEnabled == false)
    }

    @Test func cancelledHistoricalRefreshPreservesThePreviousBadge() async throws {
        let now = WhereCoreTestSupport.iso("2026-06-15T12:00:00-07:00")
        let h = try Self.makeReconciler(now: { now })
        await h.reconciler.configure(
            enabled: true,
            time: .defaultEvening,
            issueAlertsEnabled: true,
            driftThresholdMeters: Self.noIssues,
            requestAuthorization: true,
        )
        let previous = await h.spy.lastBadgeCount
        let gate = CompatibilityTestGate()
        await h.scanner.invalidate()
        await h.scanner.setBeforeHistoricalPublicationForTesting { await gate.suspend() }
        let pending = Task { await h.reconciler.reconcile() }
        await gate.waitUntilEntered()
        pending.cancel()
        await gate.resume()
        await pending.value
        #expect(await h.spy.reconcileCount == 1)
        #expect(await h.spy.lastBadgeCount == previous)
    }

    @Test func enabledIssuesReassessAfterAnotherFixOnAnAlreadyCoveredDay() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let h = try Self.makeReconciler(now: { now })
        try await h.store.perform {
            try await h.store.setManualDay(DayPresence(
                date: now,
                in: WhereCoreTestSupport.calendar(),
                regions: [.california],
            ))
        }
        await h.reconciler.configure(
            enabled: true,
            time: .defaultEvening,
            issueAlertsEnabled: true,
            driftThresholdMeters: Self.noIssues,
            requestAuthorization: true,
        )
        let before = try await h.scanner.historicalScan(
            driftThresholdMeters: Self.noIssues,
            force: false,
        )
        await h.reconciler
            .reconcileAfterIngest(changedDays: [WhereCoreTestSupport.calendar()
                    .startOfDay(for: now)])
        #expect(await h.spy.reconcileCount == 2)
        let after = try await h.scanner.historicalScan(
            driftThresholdMeters: Self.noIssues,
            force: false,
        )
        #expect(after.revision != before.revision)
    }

    @Test func configureEnabledRequestsAuthorizationAndReconciles() async throws {
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let h = try Self.makeReconciler(now: { now })
        await h.reconciler.configure(
            enabled: true,
            time: .defaultEvening,
            issueAlertsEnabled: false,
            driftThresholdMeters: Self.noIssues,
            requestAuthorization: true,
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
            requestAuthorization: true,
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
                recordingDay: nil,
            ))
        }
        await h.reconciler.configure(
            enabled: true,
            time: .defaultEvening,
            issueAlertsEnabled: false,
            driftThresholdMeters: Self.noIssues,
            requestAuthorization: true,
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
                in: WhereCoreTestSupport.calendar(),
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
            requestAuthorization: true,
        )
        let backlogOnly = try #require(await h.spy.lastBadgeCount)

        await h.reconciler.configure(
            enabled: true,
            time: .defaultEvening,
            issueAlertsEnabled: true,
            driftThresholdMeters: threshold,
            requestAuthorization: true,
        )
        let combined = try #require(await h.spy.lastBadgeCount)

        #expect(combined == backlogOnly + issueCount)
    }

    /// Issue-only reminders retain the evening schedule with no logging content.
    @Test func badgeCarriesIssueCountWhenRemindersOffButAlertsOn() async throws {
        let now = WhereCoreTestSupport.iso("2026-06-15T12:00:00-07:00")
        let h = try Self.makeReconciler(now: { now })
        try await h.store.perform {
            try await h.store.setManualDay(DayPresence(
                date: WhereCoreTestSupport.iso("2026-01-10T00:00:00-08:00"),
                in: WhereCoreTestSupport.calendar(),
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
            requestAuthorization: true,
        )

        #expect(await h.spy.lastEnabled == true)
        #expect(await h.spy.lastReminders
            .allSatisfy { !$0.remindsToLogDay && $0.missingDayCount == 0 })
        #expect(await h.spy.lastScheduleDays.count == 7)
        #expect(await h.spy.lastBadgeCount == issueCount)
    }
}

private actor SpyReminderScheduler: EveningReminderScheduling {
    private(set) var authorizationRequests = 0
    private(set) var reconcileCount = 0
    private(set) var lastBadgeCount: Int?
    private(set) var lastScheduleDays: [Date] = []
    private(set) var lastReminders: [EveningReminder] = []
    private(set) var lastTime: ReminderTime?
    private(set) var lastEnabled: Bool?

    private var authorizationGate: CompatibilityTestGate?

    func holdAuthorization(at gate: CompatibilityTestGate) {
        authorizationGate = gate
    }

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        await authorizationGate?.suspend()
        return true
    }

    func isAuthorized() async -> Bool {
        true
    }

    func cancelScheduledReminders() async {
        lastEnabled = false
        lastScheduleDays = []
    }

    func reconcile(
        badgeCount: Int,
        scheduleDays: [EveningReminder],
        reminderTime: ReminderTime,
        enabled: Bool,
    ) async {
        reconcileCount += 1
        lastBadgeCount = badgeCount
        lastScheduleDays = scheduleDays
            .map { $0.day.startOfDay(in: WhereCoreTestSupport.calendar()) }
        lastEnabled = enabled
        lastReminders = scheduleDays
        lastTime = reminderTime
    }
}
