import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

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

    private static func time(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
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
            attributor: RegionAttributor.shared,
        )
        return DataIssueScanner(
            reportReader: reader,
            attributor: RegionAttributor.shared,
            calendar: Self.calendar,
            now: now,
            scanInterval: scanInterval,
        )
    }

    /// The speed-based `FlightDayDetector` must ignore manual and
    /// evidence-implied samples: their timestamps are user-asserted, so a speed
    /// computed across them is meaningless. The exact coast-to-coast pattern
    /// that flags as GPS produces no flight issue when recorded as manual /
    /// evidence fixes (the scanner's `gpsSamplesByDay` filters them out).
    @Test func flightDetectionIgnoresManualAndEvidenceSamples() async throws {
        let store = try SwiftDataStore.inMemory()
        let fixedNow = Self.day(2026, 6, 15)
        let scanner = makeScanner(store: store, now: { fixedNow })

        let jfk = Coordinate(latitude: 40.6413, longitude: -73.7781)
        let sfo = Coordinate(latitude: 37.6213, longitude: -122.3790)
        let illinois = Coordinate(latitude: 40.29, longitude: -90.39)
        let colorado = Coordinate(latitude: 39.53, longitude: -106.16)
        let nevada = Coordinate(latitude: 38.68, longitude: -116.90)
        let evidence = SampleSource.evidenceImplied(id: UUID(), kind: .other(nil))
        let fixes: [(Int, Coordinate, SampleSource)] = [
            (8, jfk, .manual),
            (9, jfk, .manual),
            (12, jfk, .manual),
            (13, illinois, .manual),
            (14, colorado, .manual),
            (15, nevada, evidence),
            (17, sfo, .manual),
            (18, sfo, .manual),
        ]
        try await store.perform {
            for (hour, coordinate, source) in fixes {
                try await store.add(sample: LocationSample(
                    timestamp: Self.time(2026, 3, 15, hour),
                    coordinate: coordinate,
                    horizontalAccuracy: 20,
                    source: source,
                ))
            }
        }

        let issues = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california, .newYork],
            driftThresholdMeters: 10000,
            force: true,
        )
        #expect(!issues.contains { $0.category == .flightDay })
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
            return range.start.year == 2025
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

    /// The original bug's fix at the scanner level: a committed store change
    /// drops the cache *out-of-band* via the observed `store.changes()` stream,
    /// so a `force: false` reader stays honest even when no session is alive to
    /// force a rescan (a headless background ingest). Uses the real
    /// `WhereServices` assembly — which wires `storeChanges: store.changes()`
    /// into the scanner — so a severed subscription would fail this test.
    ///
    /// Dismissing a returned key is the observable lever: within the throttle
    /// interval the throttle would normally keep serving it (see
    /// `issues_throttleServesCacheUntilIntervalElapses`), but the dismissal's
    /// own commit pings `store.changes()`, so the next non-forced scan —
    /// `now` unchanged — recomputes and drops it.
    @Test func storeChangeSignalInvalidatesCacheForHeadlessReaders() async throws {
        let fixedNow = Self.day(2026, 6, 15)
        let services = try makeServices(now: { fixedNow })
        let scanner = services.resolution

        let first = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        let dismissedKey = try #require(first.first).id.storageKey

        // Commit through the journal exactly as a headless write would; this
        // pings `store.changes()`, which the scanner observes asynchronously to
        // drop its cache. No `force`, no `invalidate()` call, `now` unchanged.
        try await services.journal.dismissIssue(key: dismissedKey)

        try await waitUntil {
            let issues = try await scanner.issues(
                year: 2026,
                primaryRegions: [.california],
                driftThresholdMeters: 10000,
            )
            return !issues.contains { $0.id.storageKey == dismissedKey }
        }
    }
}

@Sendable
private func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: @Sendable () async throws -> Bool,
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if try await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("waitUntil timed out")
}
