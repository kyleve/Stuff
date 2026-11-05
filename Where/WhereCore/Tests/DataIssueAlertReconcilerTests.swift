import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

/// Covers the issue-alert intent + notification reconciliation: the alert is
/// scheduled while the current year has unresolved issues (and the user has it
/// enabled) and cleared otherwise.
struct DataIssueAlertReconcilerTests {
    private struct Harness {
        let reconciler: DataIssueAlertReconciler
        let store: SwiftDataStore
        let scanner: DataIssueScanner
        let spy: SpyDataIssueAlertScheduler
    }

    private static func makeReconciler(
        now: @escaping @Sendable () -> Date,
    ) throws -> Harness {
        let store = try SwiftDataStore.inMemory()
        let calendar = WhereCoreTestSupport.calendar()
        let aggregator = DayAggregator(calendar: calendar, timeZone: WhereCoreTestSupport.pacific)
        let reader = ReportReader(
            store: store,
            aggregator: aggregator,
            attributor: RegionAttributor.shared,
            history: LocationHistoryReader(
                store: store,
                policy: .foundation,
                geography: HistoryRegionAttribution(),
            ),
        )
        let scanner = DataIssueScanner(
            reportReader: reader,
            attributor: RegionAttributor.shared,
            calendar: calendar,
            now: now,
        )
        let spy = SpyDataIssueAlertScheduler()
        let reconciler = DataIssueAlertReconciler(
            scheduler: spy,
            scanner: scanner,
        )
        return Harness(reconciler: reconciler, store: store, scanner: scanner, spy: spy)
    }

    private static let threshold = Double(DriftThreshold.default.rawValue)

    @Test func successfulAuthorizationIsNotSupersededByAnOrdinaryRefresh() async throws {
        let now = WhereCoreTestSupport.iso("2026-06-15T12:00:00-07:00")
        let h = try Self.makeReconciler(now: { now })
        try await Self.seedPrimaryRegionWithGap(h.store)
        let gate = CompatibilityTestGate()
        await h.spy.holdAuthorization(at: gate)
        let pending = Task {
            await h.reconciler.configure(
                enabled: true,
                time: .defaultEvening,
                driftThresholdMeters: Self.threshold,
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

    @Test func historicalIssuesRemainEligibleAtYearRollover() async throws {
        let now = WhereCoreTestSupport.iso("2027-01-01T12:00:00-08:00")
        let h = try Self.makeReconciler(now: { now })
        try await Self.seedPrimaryRegionWithGap(h.store)
        await h.reconciler.configure(
            enabled: true,
            time: .defaultEvening,
            driftThresholdMeters: Self.threshold,
        )
        #expect(await h.spy.lastEnabled == true)
        #expect(await h.spy.lastBody == String(localized: .dataIssuesNotificationBody(2)))
    }

    @Test func disablingDuringScanRejectsTheOldEnabledCompletion() async throws {
        let now = WhereCoreTestSupport.iso("2026-06-15T12:00:00-07:00")
        let h = try Self.makeReconciler(now: { now })
        try await Self.seedPrimaryRegionWithGap(h.store)
        let gate = CompatibilityTestGate()
        await h.scanner.setBeforeHistoricalPublicationForTesting { await gate.suspend() }
        let pending = Task {
            await h.reconciler.configure(
                enabled: true,
                time: .defaultEvening,
                driftThresholdMeters: Self.threshold,
            )
        }
        await gate.waitUntilEntered()
        await h.reconciler.configure(
            enabled: false,
            time: .defaultEvening,
            driftThresholdMeters: Self.threshold,
        )
        await gate.resume()
        await pending.value
        #expect(await h.spy.reconcileCount == 1)
        #expect(await h.spy.lastEnabled == false)
    }

    /// A January California day makes California a primary region, so the rest of
    /// the year reads as missing days — a non-empty issue set the alert fires on.
    private static func seedPrimaryRegionWithGap(_ store: SwiftDataStore) async throws {
        try await store.perform {
            try await store.setManualDay(DayPresence(
                date: WhereCoreTestSupport.iso("2026-01-10T00:00:00-08:00"),
                in: WhereCoreTestSupport.calendar(),
                regions: [.california],
            ))
        }
    }

    @Test func schedulesAlertWhenCurrentYearHasIssues() async throws {
        let now = WhereCoreTestSupport.iso("2026-06-15T12:00:00-07:00")
        let h = try Self.makeReconciler(now: { now })
        try await Self.seedPrimaryRegionWithGap(h.store)

        await h.reconciler.configure(
            enabled: true,
            time: .defaultEvening,
            driftThresholdMeters: Self.threshold,
        )

        #expect(await h.spy.authorizationRequests == 1)
        #expect(await h.spy.lastEnabled == true)
        #expect(await h.spy.lastTime == .defaultEvening)
        let body = try #require(await h.spy.lastBody)
        #expect(body.contains("resolve"))
        #expect(!body.contains("%"))
    }

    @Test func clearsAlertWhenNoIssues() async throws {
        // An empty store at the very start of the year has no elapsed days yet,
        // so nothing is missing and there are no unresolved issues to nag about —
        // the alert must be reconciled off even though the user has it enabled.
        let now = WhereCoreTestSupport.iso("2026-01-01T12:00:00-08:00")
        let h = try Self.makeReconciler(now: { now })

        await h.reconciler.configure(
            enabled: true,
            time: .defaultEvening,
            driftThresholdMeters: Self.threshold,
        )

        #expect(await h.spy.lastEnabled == false)
    }

    @Test func configureDisabledSkipsAuthorizationAndClears() async throws {
        let now = WhereCoreTestSupport.iso("2026-06-15T12:00:00-07:00")
        let h = try Self.makeReconciler(now: { now })
        try await Self.seedPrimaryRegionWithGap(h.store)

        await h.reconciler.configure(
            enabled: false,
            time: .defaultEvening,
            driftThresholdMeters: Self.threshold,
        )

        #expect(await h.spy.authorizationRequests == 0)
        #expect(await h.spy.lastEnabled == false)
        #expect(await h.spy.lastBody == "")
    }

    @Test func reconcileClearsOnceIssuesAreResolved() async throws {
        let now = WhereCoreTestSupport.iso("2026-06-15T12:00:00-07:00")
        let h = try Self.makeReconciler(now: { now })
        try await Self.seedPrimaryRegionWithGap(h.store)

        await h.reconciler.configure(
            enabled: true,
            time: .defaultEvening,
            driftThresholdMeters: Self.threshold,
        )
        #expect(await h.spy.lastEnabled == true)

        // Resolve every outstanding issue by dismissing it — exactly what the
        // user does on the Resolve tab — then drop the scanner cache the way a
        // committed write would and reconcile again: the alert clears.
        let outstanding = try await h.scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: Self.threshold,
            force: true,
        )
        #expect(!outstanding.isEmpty)
        for issue in outstanding {
            try await h.store.perform {
                try await h.store.setIssueDismissed(true, id: issue.id)
            }
        }
        await h.scanner.invalidate()
        await h.reconciler.reconcile()

        #expect(await h.spy.lastEnabled == false)
    }
}

private actor SpyDataIssueAlertScheduler: DataIssueAlertScheduling {
    private(set) var authorizationRequests = 0
    private(set) var reconcileCount = 0
    private(set) var lastEnabled: Bool?
    private(set) var lastTime: ReminderTime?
    private(set) var lastBody: String?

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

    func reconcile(enabled: Bool, time: ReminderTime, body: String) async {
        reconcileCount += 1
        lastEnabled = enabled
        lastTime = time
        lastBody = body
    }
}
