import Foundation
import Testing
import WhereCore

struct DayAggregatorTests {
    let attributor = RegionAttributor.shared

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

    @Test func authoritativeManualDayReplacesSamples() {
        // GPS puts the day in California, but the user authoritatively corrects
        // it to New York — the wrong California attribution must disappear.
        let samples = [
            makeSample(at: "2026-07-04T10:00:00-07:00", lat: 37.7749, lng: -122.4194),
        ]
        let override = DayPresence(
            date: startOfDay(forYear: 2026, month: 7, day: 4),
            regions: [.newYork],
            isAuthoritative: true,
        )
        let report = aggregator.report(
            for: 2026,
            samples: samples,
            manualDays: [override],
            attributor: attributor,
        )
        let day = report.days.first { $0.date == override.date }
        #expect(day?.regions == [.newYork])
        #expect(report.totals == [.newYork: 1])
    }

    @Test func authoritativeManualDayOverridesAdditiveOnSameDay() {
        // An additive overlay and an authoritative one on the same day: the
        // authoritative one wins, dropping the additive region too.
        let day = startOfDay(forYear: 2026, month: 7, day: 4)
        let additive = DayPresence(date: day, regions: [.canada])
        let override = DayPresence(date: day, regions: [.newYork], isAuthoritative: true)
        let report = aggregator.report(
            for: 2026,
            samples: [],
            manualDays: [additive, override],
            attributor: attributor,
        )
        #expect(report.days.first { $0.date == day }?.regions == [.newYork])
    }

    @Test func locationsGroupInRegionSamplesByDayAndDropOthers() {
        let samples = [
            // Two CA points on the same day, plus an NY point that must be
            // excluded from the California grouping.
            makeSample(at: "2026-05-01T09:00:00-07:00", lat: 37.7749, lng: -122.4194),
            makeSample(at: "2026-05-01T17:00:00-07:00", lat: 34.0522, lng: -118.2437),
            makeSample(at: "2026-05-01T20:00:00-04:00", lat: 40.7128, lng: -74.0060),
            // A second California day.
            makeSample(at: "2026-05-09T12:00:00-07:00", lat: 37.3382, lng: -121.8863),
        ]
        let locations = aggregator.locations(
            in: .california,
            samples: samples,
            attributor: attributor,
        )
        #expect(locations.count == 2)
        #expect(locations[0].coordinates.count == 2)
        #expect(locations[1].coordinates.count == 1)
        // Sorted ascending by day.
        #expect(locations[0].date < locations[1].date)
        // The New York point never lands in the California grouping.
        #expect(!locations.flatMap(\.coordinates).contains(Coordinate(
            latitude: 40.7128,
            longitude: -74.0060,
        )))
    }

    @Test func locationsAttributeUnmappedCoordinatesToOther() {
        let samples = [
            // Mid-Pacific: inside no bundled polygon, so `.other`.
            makeSample(at: "2026-06-02T12:00:00+00:00", lat: 0, lng: -160),
        ]
        let other = aggregator.locations(in: .other, samples: samples, attributor: attributor)
        #expect(other.count == 1)
        #expect(other[0].coordinates.count == 1)

        let california = aggregator.locations(
            in: .california,
            samples: samples,
            attributor: attributor,
        )
        #expect(california.isEmpty)
    }

    @Test func representativeCoordinatePicksTheMostSampledCellPerRegion() {
        let samples = [
            // San Francisco ×3 — the dominant California cell.
            makeSample(at: "2026-07-01T12:00:00-07:00", lat: 37.7749, lng: -122.4194),
            makeSample(at: "2026-07-02T12:00:00-07:00", lat: 37.7750, lng: -122.4195),
            makeSample(at: "2026-07-03T12:00:00-07:00", lat: 37.7748, lng: -122.4193),
            // Los Angeles ×1 — also California, but fewer samples.
            makeSample(at: "2026-07-04T12:00:00-07:00", lat: 34.0522, lng: -118.2437),
            // New York ×1.
            makeSample(at: "2026-07-05T12:00:00-04:00", lat: 40.7128, lng: -74.0060),
        ]
        let representatives = aggregator.representativeCoordinates(
            samples: samples,
            attributor: attributor,
        )
        // California resolves to the San Francisco cluster, not Los Angeles.
        #expect(abs((representatives[.california]?.latitude ?? 0) - 37.7749) < 0.01)
        #expect(representatives[.newYork] != nil)
        #expect(representatives[.canada] == nil)
    }

    @Test func representativeCoordinateBreaksTiesDeterministically() {
        // Two California cells with equal sample counts; repeated runs must
        // pick the same coordinate (lower grid cell index wins on ties).
        let samples = [
            makeSample(at: "2026-07-01T12:00:00-07:00", lat: 37.7749, lng: -122.4194),
            makeSample(at: "2026-07-02T12:00:00-07:00", lat: 37.7750, lng: -122.4195),
            makeSample(at: "2026-07-03T12:00:00-07:00", lat: 34.0522, lng: -118.2437),
            makeSample(at: "2026-07-04T12:00:00-07:00", lat: 34.0523, lng: -118.2438),
        ]
        let first = aggregator.representativeCoordinates(samples: samples, attributor: attributor)
        let second = aggregator.representativeCoordinates(samples: samples, attributor: attributor)
        #expect(first[.california] == second[.california])
        #expect(first[.california] != nil)
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
            horizontalAccuracy: 0,
            source: .manual,
        )
    }

    private func startOfDay(forYear year: Int, month: Int, day: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return cal
            .date(from: DateComponents(year: year, month: month, day: day)) ??
            Date(timeIntervalSince1970: 0)
    }
}
