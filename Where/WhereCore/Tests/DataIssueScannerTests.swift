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

    @Test func issues_throttleServesCache() async throws {
        var now = Self.day(2026, 6, 15)
        let store = try SwiftDataStore.inMemory()
        let reader = ReportReader(
            store: store,
            aggregator: DayAggregator(calendar: Self.calendar, timeZone: Self.calendar.timeZone),
            attributor: .shared,
        )
        let scanner = DataIssueScanner(
            reportReader: reader,
            attributor: .shared,
            calendar: Self.calendar,
            now: { now },
            scanInterval: 3600,
        )

        let first = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        now = try #require(Self.calendar.date(byAdding: .hour, value: 1, to: now))
        let cached = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        #expect(cached.map(\.id) == first.map(\.id))
    }

    @Test func issues_forceRecomputesWithinInterval() async throws {
        let now = Self.day(2026, 6, 15)
        let services = try makeServices(now: { now })
        let scanner = services.resolution

        _ = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        _ = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
            force: true,
        )
    }

    @Test func invalidate_forcesRecompute() async throws {
        let now = Self.day(2026, 6, 15)
        let services = try makeServices(now: { now })
        let scanner = services.resolution

        _ = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
        await scanner.invalidate()
        _ = try await scanner.issues(
            year: 2026,
            primaryRegions: [.california],
            driftThresholdMeters: 10000,
        )
    }
}
