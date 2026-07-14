import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

/// Covers `CalendarDayMigration`: recovering the intended calendar day of legacy
/// manual-day rows and rewriting legacy epoch dismissal keys, robustly across the
/// time zone the device now runs in.
struct CalendarDayMigrationTests {
    /// Migrate on a Pacific device — mirrors the reported bug (data logged in New
    /// York, re-opened in San Francisco).
    private let pacific = WhereCoreTestSupport.calendar()

    private func iso(_ string: String) -> Date {
        WhereCoreTestSupport.iso(string)
    }

    // MARK: - Manual-day backfill

    @Test func backfillsDayKeyRecoveringTheWritersIntendedDay() async throws {
        let store = try SwiftDataStore.inMemory()
        // Midnight in New York (Eastern, UTC-5 in February): the exact case that
        // read back as the previous day in Pacific before this fix.
        try await store.insertLegacyManualDay(
            dateKey: iso("2026-02-08T05:00:00Z"),
            regionRaws: [Region.newYork.rawValue],
            isAuthoritative: false,
        )
        // Midnight in San Francisco (Pacific, UTC-8 in January): logged on-device,
        // must stay put.
        try await store.insertLegacyManualDay(
            dateKey: iso("2026-01-01T08:00:00Z"),
            regionRaws: [Region.california.rawValue],
            isAuthoritative: false,
        )

        try await store.runMigrations(
            [CalendarDayMigration()],
            calendar: pacific,
            versionStore: InMemoryKeyValueStore(),
        )

        let days = try await store.allManualDays()
        let byRegion = Dictionary(uniqueKeysWithValues: days.map { ($0.regions, $0.day) })
        #expect(byRegion[[.newYork]] == CalendarDay(year: 2026, month: 2, day: 8))
        #expect(byRegion[[.california]] == CalendarDay(year: 2026, month: 1, day: 1))
    }

    @Test func leavesAlreadyMigratedManualDaysUntouched() async throws {
        let store = try SwiftDataStore.inMemory()
        // A row written by the new code (dayKey already set) round-trips unchanged.
        try await store.perform {
            try await store.setManualDay(DayPresence(
                day: CalendarDay(year: 2026, month: 3, day: 15),
                regions: [.canada],
            ))
        }

        try await store.runMigrations(
            [CalendarDayMigration()],
            calendar: pacific,
            versionStore: InMemoryKeyValueStore(),
        )

        let days = try await store.allManualDays()
        #expect(days.count == 1)
        #expect(days.first?.day == CalendarDay(year: 2026, month: 3, day: 15))
    }

    @Test func isIdempotent() async throws {
        let store = try SwiftDataStore.inMemory()
        try await store.insertLegacyManualDay(
            dateKey: iso("2026-02-08T05:00:00Z"),
            regionRaws: [Region.newYork.rawValue],
            isAuthoritative: false,
        )
        let versionStore = InMemoryKeyValueStore()

        for _ in 0 ..< 2 {
            try await store.runMigrations(
                [CalendarDayMigration()],
                calendar: pacific,
                versionStore: versionStore,
            )
        }

        let days = try await store.allManualDays()
        #expect(days.count == 1)
        #expect(days.first?.day == CalendarDay(year: 2026, month: 2, day: 8))
    }

    // MARK: - Dismissal-key rewrite

    @Test func rewritesLegacyEpochDismissalKeysToCalendarDayForm() async throws {
        let store = try SwiftDataStore.inMemory()
        let nyMidnight = iso("2026-02-08T05:00:00Z")
        let legacyKey = "borderDrift:\(String(format: "%.0f", nyMidnight.timeIntervalSince1970))"
        try await store.perform {
            try await store.restoreDismissedIssue(
                DismissedIssue(key: legacyKey, dismissedAt: iso("2026-02-09T00:00:00Z")),
            )
        }

        try await store.runMigrations(
            [CalendarDayMigration()],
            calendar: pacific,
            versionStore: InMemoryKeyValueStore(),
        )

        let keys = try await store.dismissedIssueKeys()
        #expect(keys == ["borderDrift:2026-02-08"])
    }

    // MARK: - Key-rewrite rules

    @Test func rewriteLegacyIssueKeyHandlesEachFormat() {
        let earlier = iso("2026-04-10T04:00:00Z") // NY midnight (EDT, UTC-4)
        let later = iso("2026-04-11T04:00:00Z")
        let earlierEpoch = String(format: "%.0f", earlier.timeIntervalSince1970)
        let laterEpoch = String(format: "%.0f", later.timeIntervalSince1970)

        #expect(
            CalendarDayMigration.rewriteLegacyIssueKey(
                "borderDrift:\(earlierEpoch)",
                calendar: pacific,
            ) == "borderDrift:2026-04-10",
        )
        #expect(
            CalendarDayMigration.rewriteLegacyIssueKey(
                "abruptChange:\(earlierEpoch):\(laterEpoch)",
                calendar: pacific,
            ) == "abruptChange:2026-04-10:2026-04-11",
        )
    }

    @Test func rewriteLegacyIssueKeySkipsAlreadyMigratedKeys() {
        #expect(
            CalendarDayMigration.rewriteLegacyIssueKey("borderDrift:2026-04-10", calendar: pacific)
                == nil,
        )
        #expect(
            CalendarDayMigration.rewriteLegacyIssueKey(
                "abruptChange:2026-04-10:2026-04-11",
                calendar: pacific,
            ) == nil,
        )
    }
}
