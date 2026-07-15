import Foundation
import RegionKit
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
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
        #expect(days[0].day > days[1].day)
        #expect(days[0].regions == [.newYork])
        #expect(days[0].isAuthoritative)
        #expect(!days[1].isAuthoritative)
    }

    @Test func reloadReflectsADeletedEntry() async throws {
        let services = try makeServices()
        try await services.journal.addManualDay(
            date: Self.date(2026, 2, 10),
            regions: [.california],
            audit: nil,
        )
        try await services.journal.addManualDay(
            date: Self.date(2026, 6, 4),
            regions: [.newYork],
            audit: nil,
        )
        let model = LoggedDaysModel(services: services)
        await model.load(for: 2026)
        guard case let .loaded(before) = model.loadState else {
            Issue.record("expected loaded, got \(model.loadState)")
            return
        }
        #expect(before.count == 2)

        try await services.journal.clearManualDays(dates: [Self.date(2026, 2, 10)])
        await model.load(for: 2026)

        guard case let .loaded(after) = model.loadState else {
            Issue.record("expected loaded, got \(model.loadState)")
            return
        }
        #expect(after.count == 1)
        #expect(after.first?.regions == [.newYork])
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
