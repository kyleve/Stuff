import Foundation
import SnapshotTesting
import Testing
import WhereCore
import WhereData

@Suite(.snapshots(record: .missing))
struct SimulatedYearTests {
    private static let pacific = TimeZone(identifier: "America/Los_Angeles") ?? .gmt

    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = pacific
        return cal
    }

    private static func makeController() -> WhereController {
        let store = InMemoryStore()
        let source = ScriptedLocationSource()
        return WhereController(
            store: store,
            locationSource: source,
            aggregator: DayAggregator(calendar: Calendar(identifier: .gregorian), timeZone: pacific),
        )
    }

    @Test func totalsAddUpAcrossAllRegions() async throws {
        let controller = Self.makeController()
        await SimulatedYear.script(controller: controller, calendar: Self.calendar)
        let report = try await controller.yearReport(for: SimulatedYear.year)

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

    @Test func yearReport_jsonSnapshot() async throws {
        let controller = Self.makeController()
        await SimulatedYear.script(controller: controller, calendar: Self.calendar)
        let report = try await controller.yearReport(for: SimulatedYear.year)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        assertSnapshot(of: report, as: .json(encoder))
    }

    @Test func monthlySummary_dumpSnapshot() async throws {
        let controller = Self.makeController()
        await SimulatedYear.script(controller: controller, calendar: Self.calendar)
        let report = try await controller.yearReport(for: SimulatedYear.year)
        let summary = MonthlySummary.from(report: report, calendar: Self.calendar)
        assertSnapshot(of: summary.text, as: .lines)
    }

    @Test func retroactiveEntryGrowsReport() async throws {
        let controller = Self.makeController()
        await SimulatedYear.script(controller: controller, calendar: Self.calendar)
        let before = try await controller.yearReport(for: SimulatedYear.year)

        // Nov 13 had no data; backfill it with a dual-region manual entry.
        let date = Self.calendar.date(from: DateComponents(year: SimulatedYear.year, month: 11, day: 13)) ?? Date()
        try await controller.addManualDay(date: date, regions: [.california, .newYork])

        let after = try await controller.yearReport(for: SimulatedYear.year)
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
        let controller = Self.makeController()
        await SimulatedYear.script(controller: controller, calendar: Self.calendar)
        let evidence = try await controller.evidence(for: SimulatedYear.year)
        #expect(evidence.count == 3)
        let kinds = Set(evidence.map(\.kind))
        #expect(kinds == [.planeTicket, .boardingPass])
        let regions = Set(evidence.compactMap(\.region))
        #expect(regions == [.california, .europeanUnion, .canada])
    }
}
