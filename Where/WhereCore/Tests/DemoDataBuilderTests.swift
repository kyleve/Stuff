import Foundation
import RegionKit
import Testing
@_spi(Testing) import WhereCore

/// Covers the dataset demo mode runs on: that it stays inside the current
/// year, only ever claims the two regions it tracks, produces the messy shapes
/// the app is meant to demonstrate (gaps, backfills, corrections), and is the
/// same every time it's built.
@MainActor
struct DemoDataBuilderTests {
    private let calendar = WhereCoreTestSupport.calendar()

    /// Mid-October, so a comfortably-elapsed year is on the clock without the
    /// script running to the year's very edge.
    private let now = WhereCoreTestSupport.iso("2026-10-12T09:30:00Z")

    private func makeServices() throws -> WhereServices {
        try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            aggregator: DayAggregator(calendar: calendar, timeZone: calendar.timeZone),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            now: { [now] in now },
        )
    }

    private func seed(into services: WhereServices) async throws {
        try await DemoDataBuilder(now: now, calendar: calendar).seed(into: services)
    }

    @Test func tracksOnlyNewYorkAndCalifornia() async throws {
        let services = try makeServices()
        try await seed(into: services)

        let primary = try await services.primaryRegions().sorted { $0.order < $1.order }
        #expect(primary.map(\.region) == [.newYork, .california])
        // Each carries a picked look, so the demo's cards and calendar render
        // as a customized app rather than a default one.
        #expect(primary.allSatisfy { $0.appearance != nil })
    }

    @Test func coversTheCurrentYearUpToToday() async throws {
        let services = try makeServices()
        try await seed(into: services)

        let report = try await services.reports.yearReport(for: 2026)
        let days = report.days.map(\.day).sorted()
        let first = try #require(days.first)
        let last = try #require(days.last)

        #expect(first.year == 2026)
        #expect(last.year == 2026)
        // Bound to today: nothing is invented for days that haven't happened.
        #expect(last <= CalendarDay(from: now, in: calendar))
        // And it's a year's worth, not a handful of days.
        #expect(days.count > 200)
    }

    @Test func reportsOnlyTheTwoTrackedRegions() async throws {
        let services = try makeServices()
        try await seed(into: services)

        let report = try await services.reports.yearReport(for: 2026)
        let regions = Set(report.days.flatMap(\.regions))
        #expect(regions == [.newYork, .california])
        // A demo of a residency app is pointless without a second region to
        // count against, so the trips must actually land.
        #expect(report.totals[.california, default: 0] > 10)
        #expect(report.totals[.newYork, default: 0] > 100)
    }

    @Test func leavesGapsForTheResolveTabToFind() async throws {
        let services = try makeServices()
        try await seed(into: services)

        let report = try await services.reports.yearReport(for: 2026)
        let covered = Set(report.days.map(\.day))
        let elapsed = calendar.ordinality(of: .day, in: .year, for: now) ?? 0
        // Some days are deliberately left with neither GPS nor a backfill, so
        // the demo has real issues to resolve rather than a spotless year.
        #expect(covered.count < elapsed)
    }

    @Test func includesBothKindsOfManualEntry() async throws {
        let services = try makeServices()
        try await seed(into: services)

        let manual = try await services.reports.manualDays(inYear: 2026)
        let backfills = manual.filter { !$0.isAuthoritative }
        let corrections = manual.filter(\.isAuthoritative)

        // A backfill unions with GPS (a day the phone missed); a correction
        // replaces it (a day the phone got wrong). The demo shows both.
        #expect(!backfills.isEmpty)
        #expect(!corrections.isEmpty)
        #expect(backfills.allSatisfy { $0.regions == [.newYork] })
        #expect(corrections.allSatisfy { $0.regions == [.california] })
        // Each carries the audit trail the app promises for user-asserted
        // days, with an honest `nil` location rather than a fabricated fix.
        #expect(manual.allSatisfy { $0.audit?.note?.isEmpty == false })
        #expect(manual.allSatisfy { $0.audit?.location == nil })
    }

    @Test func correctionsReplaceTheDaysGpsAttribution() async throws {
        let services = try makeServices()
        try await seed(into: services)

        let report = try await services.reports.yearReport(for: 2026)
        let manual = try await services.reports.manualDays(inYear: 2026)
        // Selected outside the macros: `#require` re-expands the call it wraps,
        // and a key-path-as-function argument expands into something the
        // compiler reads as throwing.
        let corrections = manual.filter(\.isAuthoritative)
        let corrected = try #require(corrections.first)
        let reportedDays = report.days.filter { $0.day == corrected.day }
        let reported = try #require(reportedDays.first)

        // The GPS underneath says New York; the authoritative entry is what
        // the report must show.
        #expect(reported.regions == [.california])
    }

    @Test func isTheSameEveryTimeItIsBuilt() async throws {
        let first = try makeServices()
        try await seed(into: first)
        let second = try makeServices()
        try await seed(into: second)

        let firstReport = try await first.reports.yearReport(for: 2026)
        let secondReport = try await second.reports.yearReport(for: 2026)
        #expect(firstReport.totals == secondReport.totals)
        #expect(firstReport.days == secondReport.days)
    }

    @Test func earlyInTheYearProducesASmallerButValidYear() async throws {
        // Demo mode can be entered on January 3rd. It must still produce a
        // coherent year rather than trailing off the start of the calendar.
        let earlyNow = WhereCoreTestSupport.iso("2026-01-09T09:30:00Z")
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            aggregator: DayAggregator(calendar: calendar, timeZone: calendar.timeZone),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            now: { earlyNow },
        )
        try await DemoDataBuilder(now: earlyNow, calendar: calendar).seed(into: services)

        let report = try await services.reports.yearReport(for: 2026)
        let days = report.days.map(\.day).sorted()
        #expect(!days.isEmpty)
        #expect(days.allSatisfy { $0.year == 2026 })
        let last = try #require(days.last)
        #expect(last <= CalendarDay(from: earlyNow, in: calendar))
    }
}
