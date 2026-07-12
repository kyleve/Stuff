import Foundation
import RegionKit
import Testing
import WhereCore
import WhereTesting
@testable import WhereUI

/// Covers `LoggedDaysModel`'s mapping of the selected year's manual entries into
/// a `LoadState`, against an in-memory store.
@MainActor
struct LoggedDaysModelTests {
    private func makeServices() throws -> WhereServices {
        try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func loadEmptyYearIsEmptyState() async throws {
        let services = try makeServices()
        let model = LoggedDaysModel(services: services)

        await model.load(for: 2026)

        #expect(model.loadState == .empty)
    }

    @Test func loadReturnsThisYearsEntriesNewestFirst() async throws {
        let services = try makeServices()
        try await services.journal.addManualDay(
            date: Self.date(2026, 2, 10),
            regions: [.california],
            audit: nil,
        )
        try await services.journal.overrideDay(
            date: Self.date(2026, 6, 4),
            regions: [.newYork],
            audit: nil,
        )
        let model = LoggedDaysModel(services: services)

        await model.load(for: 2026)

        guard case let .loaded(days) = model.loadState else {
            Issue.record("expected loaded, got \(model.loadState)")
            return
        }
        #expect(days.count == 2)
        // Newest first: the June override precedes the February backfill.
        #expect(days[0].date > days[1].date)
        #expect(days[0].regions == [.newYork])
        #expect(days[0].isAuthoritative)
        #expect(!days[1].isAuthoritative)
    }

    @Test func loadExcludesOtherYears() async throws {
        let services = try makeServices()
        try await services.journal.addManualDay(
            date: Self.date(2025, 12, 30),
            regions: [.california],
            audit: nil,
        )
        let model = LoggedDaysModel(services: services)

        await model.load(for: 2026)

        #expect(model.loadState == .empty)
    }
}
