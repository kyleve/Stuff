import Foundation
import Testing
@testable import WhereCore

struct DataIssueScannerTests {
    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.startOfDay(for: calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
        ))!)
    }

    private func makeServices(now: @escaping @Sendable () -> Date) throws -> WhereServices {
        let store = try SwiftDataStore.inMemory()
        return WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(),
            aggregator: DayAggregator(calendar: Self.calendar, timeZone: Self.calendar.timeZone),
            now: now,
        )
    }

    private func makeScanner(
        store: SwiftDataStore,
        now: @escaping @Sendable () -> Date,
        scanInterval: TimeInterval = 3600,
    ) -> DataIssueScanner {
        let reader = ReportReader(
            store: store,
            aggregator: DayAggregator(calendar: Self.calendar, timeZone: Self.calendar.timeZone),
            attributor: .shared,
        )
        return DataIssueScanner(
            reportReader: reader,
            attributor: .shared,
            calendar: Self.calendar,
            now: now,
            scanInterval: scanInterval,
        )
    }

    @Test func issues_returnsSortedIssues() async throws {
        let fixedNow = Self.day(2026, 6, 15)
        let services = try makeServices(now: { fixedNow })
        let scanner = services.resolution

        let issues = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california, .newYork],
            driftThresholdMeters: 10000,
            force: true,
        )
        #expect(!issues.isEmpty)
        #expect(issues.allSatisfy { $0.category == .missingDays })
    }

    @Test func issues_excludesDismissedKeys() async throws {
        let fixedNow = Self.day(2026, 6, 15)
        let services = try makeServices(now: { fixedNow })
        let scanner = services.resolution

        let first = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
            force: true,
        )
        guard let issue = first.first else {
            Issue.record("Expected at least one issue")
            return
        }

        try await services.journal.dismissIssue(key: issue.id.storageKey)

        let second = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
            force: true,
        )
        #expect(second.allSatisfy { $0.id.storageKey != issue.id.storageKey })
    }

    /// Within the interval, a non-forced call serves the cached result even
    /// after the underlying dismissed set changes; once the interval elapses it
    /// recomputes and reflects the change. Dismissing one of the returned keys
    /// out from under the cache is the observable lever: a served cache still
    /// contains it, a recompute drops it.
    @Test func issues_throttleServesCacheUntilIntervalElapses() async throws {
        let clock = MutableClock(Self.day(2026, 6, 15))
        let store = try SwiftDataStore.inMemory()
        let scanner = makeScanner(store: store, now: { clock.now })

        let first = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        let dismissedKey = try #require(first.first).id.storageKey
        try await store.perform { try await store.setIssueDismissed(true, key: dismissedKey) }

        // Within the interval: the cache is served, so the new dismissal is not
        // yet reflected.
        clock.advance(by: 30 * 60)
        let cached = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        #expect(cached.map(\.id) == first.map(\.id))
        #expect(cached.contains { $0.id.storageKey == dismissedKey })

        // Past the interval: recomputes and drops the dismissed issue.
        clock.advance(by: 4 * 60 * 60)
        let recomputed = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        #expect(!recomputed.contains { $0.id.storageKey == dismissedKey })
    }

    @Test func issues_forceRecomputesWithinInterval() async throws {
        let now = Self.day(2026, 6, 15)
        let store = try SwiftDataStore.inMemory()
        let scanner = makeScanner(store: store, now: { now })

        let first = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        let dismissedKey = try #require(first.first).id.storageKey
        try await store.perform { try await store.setIssueDismissed(true, key: dismissedKey) }

        // `force` ignores the throttle and reflects the dismissal immediately,
        // without advancing `now`.
        let forced = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
            force: true,
        )
        #expect(!forced.contains { $0.id.storageKey == dismissedKey })
    }

    @Test func issues_recomputesWhenThresholdChanges() async throws {
        let now = Self.day(2026, 6, 15)
        let store = try SwiftDataStore.inMemory()
        let scanner = makeScanner(store: store, now: { now })

        let first = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        let dismissedKey = try #require(first.first).id.storageKey
        try await store.perform { try await store.setIssueDismissed(true, key: dismissedKey) }

        // A different threshold is a cache-key miss, so it recomputes even
        // within the interval and without `force`.
        let differentThreshold = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 25000,
        )
        #expect(!differentThreshold.contains { $0.id.storageKey == dismissedKey })
    }

    /// A calendar-day rollover is a cache-key miss, so the scan recomputes even
    /// within `scanInterval` and without `force` — the missing-days backlog
    /// cutoff is day-relative, so a day that crosses it mid-throttle must show up
    /// without anyone tracking the rollover. Dismissing a returned key is the
    /// observable lever: a served cache still contains it, a recompute drops it.
    @Test func issues_recomputesWhenCalendarDayRollsOver() async throws {
        // 23:30 local, so a sub-`scanInterval` advance still crosses midnight.
        let clock = MutableClock(Self.day(2026, 6, 15).addingTimeInterval(23.5 * 60 * 60))
        let store = try SwiftDataStore.inMemory()
        let scanner = makeScanner(store: store, now: { clock.now })

        let first = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        let dismissedKey = try #require(first.first).id.storageKey
        try await store.perform { try await store.setIssueDismissed(true, key: dismissedKey) }

        // 40 min later it is the next calendar day but still well inside the 1h
        // throttle, so only the day-key miss can drive the recompute that drops
        // the now-dismissed key.
        clock.advance(by: 40 * 60)
        let nextDay = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        #expect(!nextDay.contains { $0.id.storageKey == dismissedKey })
    }

    @Test func issues_recomputesWhenYearChanges() async throws {
        let now = Self.day(2026, 6, 15)
        let store = try SwiftDataStore.inMemory()
        let scanner = makeScanner(store: store, now: { now })

        let currentYear = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        // A year switch is a cache-key miss: the second call must reflect 2025
        // (its missing range starts in Jan 2025), not the cached 2026 result.
        let pastYear = try await scanner.issues(
            year: 2025,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        #expect(currentYear.map(\.id) != pastYear.map(\.id))
        #expect(pastYear.contains { issue in
            guard case let .backfill(range) = issue.resolution else { return false }
            return Self.calendar.component(.year, from: range.start) == 2025
        })
    }

    @Test func invalidate_forcesRecompute() async throws {
        let now = Self.day(2026, 6, 15)
        let store = try SwiftDataStore.inMemory()
        let scanner = makeScanner(store: store, now: { now })

        let first = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        let dismissedKey = try #require(first.first).id.storageKey
        try await store.perform { try await store.setIssueDismissed(true, key: dismissedKey) }

        await scanner.invalidate()

        // After invalidation the next call recomputes despite being within the
        // interval, so the dismissal is reflected.
        let afterInvalidate = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        #expect(!afterInvalidate.contains { $0.id.storageKey == dismissedKey })
    }
}
