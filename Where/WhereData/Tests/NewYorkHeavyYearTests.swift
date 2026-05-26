import Foundation
import Testing
import WhereCore
import WhereData

/// Mirror image of `SimulatedYearTests`: scripts a year with far more
/// time in New York than in California to verify the aggregator and
/// region attributor behave symmetrically when NY > CA. Exercises
/// several distinct NY coordinates (Manhattan, Brooklyn, Long Island,
/// Albany, Rochester, Buffalo) so the test fails if the bundled NY
/// polygon ever loses coverage of any of them.
struct NewYorkHeavyYearTests {
    private static let pacific = TimeZone(identifier: "America/Los_Angeles") ?? .gmt

    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = pacific
        return cal
    }

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

    /// 304 days NY (across 6 different NY coordinates) and 61 days CA,
    /// no flights / manual entries / gaps. Designed so the arithmetic
    /// is trivial to eyeball.
    private static func script(controller: WhereController) async {
        let plan: [(month: Int, days: Int, lat: Double, lng: Double)] = [
            (1, 31, manhattan.lat, manhattan.lng),
            (2, 28, brooklyn.lat, brooklyn.lng),
            (3, 31, longIsland.lat, longIsland.lng),
            (4, 30, albany.lat, albany.lng),
            (5, 31, sf.lat, sf.lng),
            (6, 30, la.lat, la.lng),
            (7, 31, rochester.lat, rochester.lng),
            (8, 31, buffalo.lat, buffalo.lng),
            (9, 30, manhattan.lat, manhattan.lng),
            (10, 31, brooklyn.lat, brooklyn.lng),
            (11, 30, albany.lat, albany.lng),
            (12, 31, manhattan.lat, manhattan.lng),
        ]
        for entry in plan {
            for day in 1 ... entry.days {
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

    @Test func totalsHaveNewYorkFarAheadOfCalifornia() async throws {
        let controller = Self.makeController()
        await Self.script(controller: controller)
        let report = try await controller.yearReport(for: Self.year)

        #expect(report.totals[.newYork] == 304)
        #expect(report.totals[.california] == 61)
        #expect(report.totals[.other, default: 0] == 0)
        #expect((report.totals[.newYork] ?? 0) > (report.totals[.california] ?? 0))
        #expect(report.days.count == 365)
    }

    @Test func perMonthBreakdown() async throws {
        let controller = Self.makeController()
        await Self.script(controller: controller)
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
        await Self.script(controller: controller)
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
}
