import Foundation
import Testing
import WhereCore

/// Mirror image of `SimulatedYearTests`: scripts a year with far more
/// time in New York than in California to verify the aggregator and
/// region attributor behave symmetrically when NY > CA. Exercises
/// several distinct NY coordinates (Manhattan, Brooklyn, Long Island,
/// Albany, Rochester, Buffalo) so the test fails if the bundled NY
/// polygon ever loses coverage of any of them.
///
/// Also includes bare-majority tests (CA majority by 1 day, NY
/// majority by 1 day) to verify the totals correctly identify the
/// majority region even at the tightest possible split.
struct NewYorkHeavyYearTests {
    private static let pacific = TimeZone(identifier: "America/Los_Angeles")!

    private static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = pacific
        return cal
    }()

    private static func makeController() -> WhereController {
        WhereController(
            store: InMemoryStore(),
            locationSource: ScriptedLocationSource(),
            aggregator: DayAggregator(
                calendar: Calendar(identifier: .gregorian),
                timeZone: pacific,
            ),
        )
    }

    private static let year = 2026

    // (lat, lng) coordinates known to fall inside the named state polygon.
    private static let manhattan = (lat: 40.7128, lng: -74.0060)
    private static let brooklyn = (lat: 40.6782, lng: -73.9442)
    private static let longIsland = (lat: 40.7891, lng: -73.1350)
    private static let albany = (lat: 42.6526, lng: -73.7562)
    private static let rochester = (lat: 43.1566, lng: -77.6088)
    private static let buffalo = (lat: 42.8864, lng: -78.8784)
    private static let sf = (lat: 37.7749, lng: -122.4194)
    private static let la = (lat: 34.0522, lng: -118.2437)

    private typealias PlanEntry = (
        month: Int,
        days: ClosedRange<Int>,
        lat: Double,
        lng: Double
    )

    private static func script(controller: WhereController, plan: [PlanEntry]) async {
        for entry in plan {
            for day in entry.days {
                let date = calendar.date(from: DateComponents(
                    year: year,
                    month: entry.month,
                    day: day,
                    hour: 12,
                )) ?? Date()
                try? await controller.ingest(LocationSample(
                    timestamp: date,
                    coordinate: Coordinate(latitude: entry.lat, longitude: entry.lng),
                    horizontalAccuracy: 0,
                    source: .gpsSignificantChange,
                ))
            }
        }
    }

    // MARK: - NY heavy (304 NY / 61 CA)

    /// 304 days NY (across 6 different NY coordinates) and 61 days CA,
    /// no flights / manual entries / gaps.
    private static let newYorkHeavyPlan: [PlanEntry] = [
        (1, 1 ... 31, manhattan.lat, manhattan.lng),
        (2, 1 ... 28, brooklyn.lat, brooklyn.lng),
        (3, 1 ... 31, longIsland.lat, longIsland.lng),
        (4, 1 ... 30, albany.lat, albany.lng),
        (5, 1 ... 31, sf.lat, sf.lng),
        (6, 1 ... 30, la.lat, la.lng),
        (7, 1 ... 31, rochester.lat, rochester.lng),
        (8, 1 ... 31, buffalo.lat, buffalo.lng),
        (9, 1 ... 30, manhattan.lat, manhattan.lng),
        (10, 1 ... 31, brooklyn.lat, brooklyn.lng),
        (11, 1 ... 30, albany.lat, albany.lng),
        (12, 1 ... 31, manhattan.lat, manhattan.lng),
    ]

    @Test func totalsHaveNewYorkFarAheadOfCalifornia() async throws {
        let controller = Self.makeController()
        await Self.script(controller: controller, plan: Self.newYorkHeavyPlan)
        let report = try await controller.yearReport(for: Self.year)

        #expect(report.totals[.newYork] == 304)
        #expect(report.totals[.california] == 61)
        #expect(report.totals[.other, default: 0] == 0)
        #expect((report.totals[.newYork] ?? 0) > (report.totals[.california] ?? 0))
        #expect(report.days.count == 365)
    }

    @Test func perMonthBreakdown() async throws {
        let controller = Self.makeController()
        await Self.script(controller: controller, plan: Self.newYorkHeavyPlan)
        let report = try await controller.yearReport(for: Self.year)

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

        #expect(totals(1) == [.newYork: 31])
        #expect(totals(2) == [.newYork: 28])
        #expect(totals(3) == [.newYork: 31])
        #expect(totals(4) == [.newYork: 30])
        #expect(totals(5) == [.california: 31])
        #expect(totals(6) == [.california: 30])
        #expect(totals(7) == [.newYork: 31])
        #expect(totals(8) == [.newYork: 31])
        #expect(totals(9) == [.newYork: 30])
        #expect(totals(10) == [.newYork: 31])
        #expect(totals(11) == [.newYork: 30])
        #expect(totals(12) == [.newYork: 31])
    }

    @Test func everyNewYorkDayResolvesToNewYorkOnly() async throws {
        let controller = Self.makeController()
        await Self.script(controller: controller, plan: Self.newYorkHeavyPlan)
        let report = try await controller.yearReport(for: Self.year)

        // Months 1-4 and 7-12 all script to distinct NY coordinates;
        // no day from those months should leak into CA, .other, etc.
        let newYorkMonths: Set = [1, 2, 3, 4, 7, 8, 9, 10, 11, 12]
        for day in report.days {
            let month = Self.calendar.component(.month, from: day.date)
            if newYorkMonths.contains(month) {
                #expect(
                    day.regions == [.newYork],
                    "Day in month \(month) attributed to \(day.regions)",
                )
            } else {
                #expect(
                    day.regions == [.california],
                    "Day in month \(month) attributed to \(day.regions)",
                )
            }
        }
    }

    // MARK: - Bare majorities (1-day margin)

    // 2026 is a non-leap year (365 days). Tightest possible majority
    // is 183 vs 182. Jan-Jun = 31+28+31+30+31+30 = 181 days, so giving
    // the "majority" region those 6 months + Jul 1-2 (183 days) and
    // the "minority" region Jul 3-31 + Aug-Dec (29+153 = 182 days)
    // produces the tightest split possible.

    private static let californiaBareMajorityPlan: [PlanEntry] = [
        (1, 1 ... 31, sf.lat, sf.lng),
        (2, 1 ... 28, la.lat, la.lng),
        (3, 1 ... 31, sf.lat, sf.lng),
        (4, 1 ... 30, la.lat, la.lng),
        (5, 1 ... 31, sf.lat, sf.lng),
        (6, 1 ... 30, la.lat, la.lng),
        (7, 1 ... 2, sf.lat, sf.lng),
        (7, 3 ... 31, manhattan.lat, manhattan.lng),
        (8, 1 ... 31, brooklyn.lat, brooklyn.lng),
        (9, 1 ... 30, longIsland.lat, longIsland.lng),
        (10, 1 ... 31, albany.lat, albany.lng),
        (11, 1 ... 30, rochester.lat, rochester.lng),
        (12, 1 ... 31, buffalo.lat, buffalo.lng),
    ]

    private static let newYorkBareMajorityPlan: [PlanEntry] = [
        (1, 1 ... 31, manhattan.lat, manhattan.lng),
        (2, 1 ... 28, brooklyn.lat, brooklyn.lng),
        (3, 1 ... 31, longIsland.lat, longIsland.lng),
        (4, 1 ... 30, albany.lat, albany.lng),
        (5, 1 ... 31, rochester.lat, rochester.lng),
        (6, 1 ... 30, buffalo.lat, buffalo.lng),
        (7, 1 ... 2, manhattan.lat, manhattan.lng),
        (7, 3 ... 31, sf.lat, sf.lng),
        (8, 1 ... 31, la.lat, la.lng),
        (9, 1 ... 30, sf.lat, sf.lng),
        (10, 1 ... 31, la.lat, la.lng),
        (11, 1 ... 30, sf.lat, sf.lng),
        (12, 1 ... 31, la.lat, la.lng),
    ]

    @Test func californiaWinsBy_oneDay() async throws {
        let controller = Self.makeController()
        await Self.script(controller: controller, plan: Self.californiaBareMajorityPlan)
        let report = try await controller.yearReport(for: Self.year)

        #expect(report.totals[.california] == 183)
        #expect(report.totals[.newYork] == 182)
        #expect(report.totals[.other, default: 0] == 0)
        #expect((report.totals[.california] ?? 0) - (report.totals[.newYork] ?? 0) == 1)
        #expect(report.days.count == 365)
    }

    @Test func newYorkWinsBy_oneDay() async throws {
        let controller = Self.makeController()
        await Self.script(controller: controller, plan: Self.newYorkBareMajorityPlan)
        let report = try await controller.yearReport(for: Self.year)

        #expect(report.totals[.newYork] == 183)
        #expect(report.totals[.california] == 182)
        #expect(report.totals[.other, default: 0] == 0)
        #expect((report.totals[.newYork] ?? 0) - (report.totals[.california] ?? 0) == 1)
        #expect(report.days.count == 365)
    }

    // MARK: - Back-and-forth every ~8 weeks (2-month stretches)

    // Six 2-month stretches (~8-9 weeks each), alternating between
    // CA and NY. 2026's calendar gives the second region in each
    // pairing slightly more days (3-day margin), so swapping which
    // region starts the year flips the majority. Each stretch uses a
    // different city to also exercise polygon coverage.

    private static let backAndForthFavorsNewYorkPlan: [PlanEntry] = [
        (1, 1 ... 31, sf.lat, sf.lng),
        (2, 1 ... 28, la.lat, la.lng),
        (3, 1 ... 31, manhattan.lat, manhattan.lng),
        (4, 1 ... 30, brooklyn.lat, brooklyn.lng),
        (5, 1 ... 31, sf.lat, sf.lng),
        (6, 1 ... 30, la.lat, la.lng),
        (7, 1 ... 31, longIsland.lat, longIsland.lng),
        (8, 1 ... 31, albany.lat, albany.lng),
        (9, 1 ... 30, sf.lat, sf.lng),
        (10, 1 ... 31, la.lat, la.lng),
        (11, 1 ... 30, rochester.lat, rochester.lng),
        (12, 1 ... 31, buffalo.lat, buffalo.lng),
    ]

    private static let backAndForthFavorsCaliforniaPlan: [PlanEntry] = [
        (1, 1 ... 31, manhattan.lat, manhattan.lng),
        (2, 1 ... 28, brooklyn.lat, brooklyn.lng),
        (3, 1 ... 31, sf.lat, sf.lng),
        (4, 1 ... 30, la.lat, la.lng),
        (5, 1 ... 31, longIsland.lat, longIsland.lng),
        (6, 1 ... 30, albany.lat, albany.lng),
        (7, 1 ... 31, sf.lat, sf.lng),
        (8, 1 ... 31, la.lat, la.lng),
        (9, 1 ... 30, rochester.lat, rochester.lng),
        (10, 1 ... 31, buffalo.lat, buffalo.lng),
        (11, 1 ... 30, sf.lat, sf.lng),
        (12, 1 ... 31, la.lat, la.lng),
    ]

    @Test func backAndForthEvery8Weeks_endsWithNewYorkAhead() async throws {
        let controller = Self.makeController()
        await Self.script(controller: controller, plan: Self.backAndForthFavorsNewYorkPlan)
        let report = try await controller.yearReport(for: Self.year)

        // CA stretches: Jan-Feb (59), May-Jun (61), Sep-Oct (61) = 181
        // NY stretches: Mar-Apr (61), Jul-Aug (62), Nov-Dec (61) = 184
        #expect(report.totals[.california] == 181)
        #expect(report.totals[.newYork] == 184)
        #expect(report.totals[.other, default: 0] == 0)
        #expect((report.totals[.newYork] ?? 0) > (report.totals[.california] ?? 0))
        #expect(report.days.count == 365)
    }

    @Test func backAndForthEvery8Weeks_endsWithCaliforniaAhead() async throws {
        let controller = Self.makeController()
        await Self.script(controller: controller, plan: Self.backAndForthFavorsCaliforniaPlan)
        let report = try await controller.yearReport(for: Self.year)

        // NY stretches: Jan-Feb (59), May-Jun (61), Sep-Oct (61) = 181
        // CA stretches: Mar-Apr (61), Jul-Aug (62), Nov-Dec (61) = 184
        #expect(report.totals[.newYork] == 181)
        #expect(report.totals[.california] == 184)
        #expect(report.totals[.other, default: 0] == 0)
        #expect((report.totals[.california] ?? 0) > (report.totals[.newYork] ?? 0))
        #expect(report.days.count == 365)
    }
}
