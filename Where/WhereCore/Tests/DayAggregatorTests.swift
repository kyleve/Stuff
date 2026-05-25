import Foundation
import Testing
import WhereCore

struct DayAggregatorTests {
    let attributor = RegionAttributor.bundled

    /// All tests pin themselves to America/Los_Angeles so behavior doesn't
    /// shift with the test runner's clock or default locale.
    private var aggregator: DayAggregator {
        DayAggregator(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "America/Los_Angeles") ?? .gmt,
        )
    }

    @Test func singleRegionDay() {
        let samples = [
            makeSample(at: "2026-03-15T09:00:00-07:00", lat: 37.7749, lng: -122.4194),
            makeSample(at: "2026-03-15T18:00:00-07:00", lat: 37.7749, lng: -122.4194),
        ]
        let days = aggregator.aggregate(samples: samples, attributor: attributor)
        #expect(days.count == 1)
        #expect(days[0].regions == [.california])
    }

    @Test func dualRegionDay_crossCountryFlight() {
        let samples = [
            makeSample(at: "2026-04-10T08:00:00-07:00", lat: 37.7749, lng: -122.4194),
            makeSample(at: "2026-04-10T20:00:00-04:00", lat: 40.7128, lng: -74.0060),
        ]
        let days = aggregator.aggregate(samples: samples, attributor: attributor)
        #expect(days.count == 1)
        #expect(days[0].regions == [.california, .newYork])
    }

    @Test func transatlanticFlight_crossingMidnight() {
        let samples = [
            makeSample(at: "2026-05-01T20:00:00-04:00", lat: 40.7128, lng: -74.0060),
            makeSample(at: "2026-05-02T09:00:00+02:00", lat: 48.8566, lng: 2.3522),
        ]
        let days = aggregator.aggregate(samples: samples, attributor: attributor)
        let regionsByDay = days.map(\.regions)
        #expect(regionsByDay.count == 2)
        #expect(regionsByDay[0] == [.newYork])
        #expect(regionsByDay[1] == [.europeanUnion])
    }

    @Test func neitherRegionDay_mexicoStopover() {
        let samples = [
            makeSample(at: "2026-06-01T12:00:00-06:00", lat: 19.4326, lng: -99.1332),
        ]
        let days = aggregator.aggregate(samples: samples, attributor: attributor)
        #expect(days.count == 1)
        #expect(days[0].regions == [.other])
    }

    @Test func emptyInput_givesEmptyResult() {
        let days = aggregator.aggregate(samples: [], attributor: attributor)
        #expect(days.isEmpty)
    }

    @Test func lateNightPacificStillSameDay() throws {
        let samples = [
            makeSample(at: "2026-03-15T23:59:00-07:00", lat: 37.7749, lng: -122.4194),
        ]
        let days = aggregator.aggregate(samples: samples, attributor: attributor)
        #expect(days.count == 1)
        let pt = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = pt
        #expect(cal.component(.day, from: days[0].date) == 15)
    }

    @Test func crossMidnightInPacificButSameNewYorkDay_isTwoDays() {
        // Both samples in NYC; both fall on March 16 in Eastern Time but
        // straddle midnight in Pacific Time, so the PT aggregator splits them.
        let samples = [
            makeSample(at: "2026-03-16T02:00:00-04:00", lat: 40.7128, lng: -74.0060),
            makeSample(at: "2026-03-16T04:00:00-04:00", lat: 40.7128, lng: -74.0060),
        ]
        let days = aggregator.aggregate(samples: samples, attributor: attributor)
        #expect(days.count == 2)
        #expect(days.allSatisfy { $0.regions == [.newYork] })
    }

    @Test func manualDayUnionsWithSamples() {
        let samples = [
            makeSample(at: "2026-07-04T10:00:00-07:00", lat: 37.7749, lng: -122.4194),
        ]
        let manual = DayPresence(
            date: startOfDay(forYear: 2026, month: 7, day: 4),
            regions: [.newYork],
        )
        let report = aggregator.report(
            for: 2026,
            samples: samples,
            manualDays: [manual],
            attributor: attributor,
        )
        let day = report.days.first { $0.date == manual.date }
        #expect(day != nil)
        #expect(day?.regions == [.california, .newYork])
    }

    @Test func reportFiltersOtherYears() {
        let samples = [
            makeSample(at: "2025-12-31T12:00:00-08:00", lat: 37.7749, lng: -122.4194),
            makeSample(at: "2026-01-15T12:00:00-08:00", lat: 37.7749, lng: -122.4194),
            makeSample(at: "2027-02-01T12:00:00-08:00", lat: 37.7749, lng: -122.4194),
        ]
        let report = aggregator.report(
            for: 2026,
            samples: samples,
            attributor: attributor,
        )
        #expect(report.days.count == 1)
        #expect(report.totals == [.california: 1])
    }

    // MARK: - Helpers

    private func makeSample(at iso: String, lat: Double, lng: Double) -> LocationSample {
        let formatter = ISO8601DateFormatter()
        return LocationSample(
            timestamp: formatter.date(from: iso) ?? Date(timeIntervalSince1970: 0),
            coordinate: Coordinate(latitude: lat, longitude: lng),
            source: .manual,
        )
    }

    private func startOfDay(forYear year: Int, month: Int, day: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return cal.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }
}
