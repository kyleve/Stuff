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

    private func makeServices(now clock: Date? = nil) throws -> WhereServices {
        let instant = clock ?? now
        return try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: ScriptedLocationSource(),
            aggregator: DayAggregator(calendar: calendar, timeZone: calendar.timeZone),
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            now: { instant },
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

    @Test func leavesAFewRecentDaysForTheResolveTabToFind() async throws {
        let services = try makeServices()
        try await seed(into: services)

        let unlogged = try await unloggedDays(in: services)

        // Some days are deliberately left with neither GPS nor a backfill, so
        // the demo has real issues to resolve rather than a spotless year.
        #expect(!unlogged.isEmpty)
        // But only a few, and only recent ones: someone using the app deals
        // with problems as they come up, so a backlog would misrepresent it —
        // and a demo opening on a wall of issues reads as a broken app.
        #expect(unlogged.count <= 3)
        let today = CalendarDay(from: now, in: calendar)
        let fortnightAgo = today.adding(days: -14)
        #expect(unlogged.allSatisfy { $0 > fortnightAgo && $0 < today })
    }

    /// Days in the demo year with neither a GPS sample nor a manual entry — what
    /// the app surfaces as missing-day issues.
    private func unloggedDays(in services: WhereServices) async throws -> [CalendarDay] {
        let report = try await services.reports.yearReport(for: 2026)
        let covered = Set(report.days.map(\.day))
        let elapsed = calendar.ordinality(of: .day, in: .year, for: now) ?? 0
        let firstDay = CalendarDay(year: 2026, month: 1, day: 1)
        return (0 ..< elapsed)
            .map { firstDay.adding(days: $0) }
            .filter { !covered.contains($0) }
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

    @Test(arguments: [
        "2026-01-01T09:30:00Z",
        "2026-10-12T09:30:00Z",
    ])
    func configuredIssueCategoriesAreExact(iso: String) async throws {
        let requestedDate = WhereCoreTestSupport.iso(iso)
        let categories = DataIssueCategory.allCases
        for mask in 0 ..< (1 << categories.count) {
            let selected = Set(categories.enumerated().compactMap { index, category in
                mask & (1 << index) == 0 ? nil : category
            })
            let configuration = DemoDataBuilder.Configuration(issueCategories: selected)
            let referenceDate = configuration.referenceDate(
                from: requestedDate,
                calendar: calendar,
            )
            let services = try makeServices(now: referenceDate)
            try await DemoDataBuilder(
                now: referenceDate,
                calendar: calendar,
                configuration: configuration,
            ).seed(into: services)

            let issues = try await services.resolution.issues(
                year: 2026,
                primaryRegions: [.newYork, .california],
                driftThresholdMeters: DriftThreshold.default.meters,
                force: true,
            )
            #expect(Set(issues.map(\.category)) == selected, "Configuration mask \(mask)")
        }
    }

    @Test func demoReferenceDateAdvancesOnlyAsFarAsItsFixturesNeed() {
        let januaryFirst = WhereCoreTestSupport.iso("2026-01-01T09:30:00Z")

        #expect(
            DemoDataBuilder.Configuration(issueCategories: [])
                .referenceDate(from: januaryFirst, calendar: calendar) == januaryFirst,
        )
        #expect(
            calendar.ordinality(
                of: .day,
                in: .year,
                for: DemoDataBuilder.Configuration.allIssues.referenceDate(
                    from: januaryFirst,
                    calendar: calendar,
                ),
            ) == 5,
        )
    }

    /// The shape has to survive being entered at any point in the year, which
    /// is the bug this pins: with fixed-size trips and gaps, a January demo was
    /// more than half unlogged and a February one counted more California days
    /// than New York ones.
    @Test(arguments: [
        "2026-01-06T09:30:00Z", // a week in
        "2026-01-21T09:30:00Z", // three weeks
        "2026-02-16T09:30:00Z", // mid-February, where California used to win
        "2026-04-01T09:30:00Z",
        "2026-07-15T09:30:00Z",
        "2026-12-28T09:30:00Z", // a full year
    ])
    func holdsItsShapeWhereverInTheYearItIsEntered(iso: String) async throws {
        let entered = WhereCoreTestSupport.iso(iso)
        let services = try makeServices(now: entered)
        try await DemoDataBuilder(now: entered, calendar: calendar).seed(into: services)

        let report = try await services.reports.yearReport(for: 2026)
        let elapsed = calendar.ordinality(of: .day, in: .year, for: entered) ?? 0
        let newYork = report.totals[.newYork, default: 0]
        let california = report.totals[.california, default: 0]

        // Home is home: New York holds the clear majority of days, so the demo
        // reads as someone who lives there and travels — never the inverse.
        #expect(newYork > california)
        #expect(Double(newYork) / Double(elapsed) > 0.6)
        // California still shows up, or there is nothing to demonstrate.
        #expect(california > 0)
        // And the year stays inside itself, up to today.
        let days = report.days.map(\.day).sorted()
        #expect(days.allSatisfy { $0.year == 2026 })
        let last = try #require(days.last)
        #expect(last <= CalendarDay(from: entered, in: calendar))
    }

    @Test(arguments: [
        "2026-01-06T09:30:00Z",
        "2026-02-16T09:30:00Z",
        "2026-07-15T09:30:00Z",
        "2026-12-28T09:30:00Z",
    ])
    func keepsOutstandingIssuesFewAndRecent(iso: String) async throws {
        let entered = WhereCoreTestSupport.iso(iso)
        let services = try makeServices(now: entered)
        try await DemoDataBuilder(now: entered, calendar: calendar).seed(into: services)

        let report = try await services.reports.yearReport(for: 2026)
        let covered = Set(report.days.map(\.day))
        let elapsed = calendar.ordinality(of: .day, in: .year, for: entered) ?? 0
        let firstDay = CalendarDay(year: 2026, month: 1, day: 1)
        let unlogged = (0 ..< elapsed)
            .map { firstDay.adding(days: $0) }
            .filter { !covered.contains($0) }

        let today = CalendarDay(from: entered, in: calendar)
        #expect(!unlogged.isEmpty)
        #expect(unlogged.count <= 3)
        #expect(unlogged.allSatisfy { $0 > today.adding(days: -14) && $0 < today })
    }
}
