import Foundation
import Testing
import WhereCore

struct SimulatedYearTests {
    private static let pacific = WhereCoreTestSupport.pacific

    private static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = pacific
        return cal
    }()

    private static func makeServices() throws -> WhereServices {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource()
        return WhereServices(
            store: store,
            locationSource: source,
            aggregator: DayAggregator(
                calendar: Calendar(identifier: .gregorian),
                timeZone: pacific,
            ),
        )
    }

    /// Scripted services and their year report. Scripting the year is the
    /// expensive part (hundreds of samples, point-in-polygon attribution, a
    /// SwiftData transaction), so the read-only tests below share one copy.
    private struct Fixture {
        let services: WhereServices
        let report: YearReport
    }

    /// The scripted year is identical for every read-only assertion, so do
    /// the work exactly once and reuse it. Swift Testing instantiates the
    /// suite per test, so the cache has to live at type scope.
    /// `retroactiveEntryGrowsReport` mutates the store, so it keeps its own
    /// services rather than touching this shared one.
    private static let fixture = Task<Fixture, Error> {
        let services = try makeServices()
        await SimulatedYear.script(services: services, calendar: calendar)
        let report = try await services.reports.yearReport(for: SimulatedYear.year)
        return Fixture(services: services, report: report)
    }

    @Test func totalsAddUpAcrossAllRegions() async throws {
        let report = try await Self.fixture.value.report

        #expect(report.totals[.california] == 250)
        #expect(report.totals[.newYork] == 94)
        #expect(report.totals[.canada] == 7)
        #expect(report.totals[.europeanUnion] == 13)
        #expect(report.totals[.other, default: 0] == 0)

        let attributionSum = report.totals.values.reduce(0, +)
        let dualRegionDays = report.days.count(where: { $0.regions.count > 1 })
        let singleRegionDays = report.days.count - dualRegionDays
        // Every dual-region day contributes 2; every other day contributes 1.
        #expect(attributionSum == singleRegionDays + 2 * dualRegionDays)

        // 8 specific flight days planned in the fixture.
        #expect(dualRegionDays == 8)

        // 365 calendar days - 7 (Sep 16-22 gap) - 2 (Nov 13-14 gap) = 356.
        #expect(report.days.count == 356)
    }

    @Test func yearReport_perMonthBreakdown() async throws {
        let report = try await Self.fixture.value.report

        let byMonth = Dictionary(grouping: report.days) {
            Self.calendar.component(.month, from: $0.date)
        }

        func totals(_ month: Int) -> [Region: Int] {
            var counts: [Region: Int] = [:]
            for day in byMonth[month] ?? [] {
                for region in day.regions {
                    counts[region, default: 0] += 1
                }
            }
            return counts
        }
        func dualRegionDayCount(_ month: Int) -> Int {
            (byMonth[month] ?? []).count { $0.regions.count > 1 }
        }

        #expect(totals(1) == [.california: 31])
        #expect(totals(2) == [.california: 28])
        #expect(totals(3) == [.california: 16, .newYork: 16])
        #expect(totals(4) == [.california: 15, .newYork: 16])
        #expect(totals(5) == [.california: 15, .europeanUnion: 13, .newYork: 5])
        #expect(totals(6) == [.canada: 7, .newYork: 25])
        #expect(totals(7) == [.california: 16, .newYork: 16])
        #expect(totals(8) == [.california: 31])
        #expect(totals(9) == [.california: 23])
        #expect(totals(10) == [.california: 31])
        #expect(totals(11) == [.california: 28])
        #expect(totals(12) == [.california: 16, .newYork: 16])

        #expect(dualRegionDayCount(3) == 1)
        #expect(dualRegionDayCount(4) == 1)
        #expect(dualRegionDayCount(5) == 2)
        #expect(dualRegionDayCount(6) == 2)
        #expect(dualRegionDayCount(7) == 1)
        #expect(dualRegionDayCount(12) == 1)
    }

    @Test func retroactiveEntryGrowsReport() async throws {
        let services = try Self.makeServices()
        await SimulatedYear.script(services: services, calendar: Self.calendar)
        let before = try await services.reports.yearReport(for: SimulatedYear.year)

        // Nov 13 had no data; backfill it with a dual-region manual entry.
        let date = Self.calendar.date(from: DateComponents(
            year: SimulatedYear.year,
            month: 11,
            day: 13,
        )) ?? Date()
        try await services.journal.addManualDay(
            date: date,
            regions: [.california, .newYork],
            audit: nil,
        )

        let after = try await services.reports.yearReport(for: SimulatedYear.year)
        #expect(after.days.count == before.days.count + 1)

        let nov13 = after.days.first { day in
            let components = Self.calendar.dateComponents([.month, .day], from: day.date)
            return components.month == 11 && components.day == 13
        }
        #expect(nov13?.regions == [.california, .newYork])
        #expect((after.totals[.california] ?? 0) == (before.totals[.california] ?? 0) + 1)
        #expect((after.totals[.newYork] ?? 0) == (before.totals[.newYork] ?? 0) + 1)
    }

    @Test func evidenceStillRetrievableAfterScripting() async throws {
        let evidence = try await Self.fixture.value.services.journal
            .evidence(for: SimulatedYear.year)
        #expect(evidence.count == 3)
        let kinds = Set(evidence.map(\.kind))
        #expect(kinds == [.planeTicket, .boardingPass])
        let regions = Set(evidence.compactMap(\.region))
        #expect(regions == [.california, .europeanUnion, .canada])
    }
}
