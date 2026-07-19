import Foundation
import RegionKit
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

    /// The Pacific calendar the aggregator buckets days in — used to pin manual
    /// `DayPresence` entries to the same `CalendarDay` the aggregator computes.
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return cal
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

    @Test func lateNightPacificStillSameDay() {
        let samples = [
            makeSample(at: "2026-03-15T23:59:00-07:00", lat: 37.7749, lng: -122.4194),
        ]
        let days = aggregator.aggregate(samples: samples, attributor: attributor)
        #expect(days.count == 1)
        #expect(days[0].day == CalendarDay(year: 2026, month: 3, day: 15))
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
            in: calendar,
            regions: [.newYork],
        )
        let report = aggregator.report(
            for: 2026,
            samples: samples,
            manualDays: [manual],
            attributor: attributor,
        )
        let day = report.days.first { $0.day == manual.day }
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
            in: calendar,
            regions: [.newYork],
            isAuthoritative: true,
        )
        let report = aggregator.report(
            for: 2026,
            samples: samples,
            manualDays: [override],
            attributor: attributor,
        )
        let day = report.days.first { $0.day == override.day }
        #expect(day?.regions == [.newYork])
        #expect(report.totals == [.newYork: 1])
    }

    @Test func authoritativeManualDayOverridesAdditiveOnSameDay() {
        // An additive overlay and an authoritative one on the same day: the
        // authoritative one wins, dropping the additive region too.
        let day = startOfDay(forYear: 2026, month: 7, day: 4)
        let additive = DayPresence(date: day, in: calendar, regions: [.canada])
        let override = DayPresence(
            date: day,
            in: calendar,
            regions: [.newYork],
            isAuthoritative: true,
        )
        let report = aggregator.report(
            for: 2026,
            samples: [],
            manualDays: [additive, override],
            attributor: attributor,
        )
        #expect(report.days.first { $0.day == CalendarDay(from: day, in: calendar) }?
            .regions == [.newYork])
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
        #expect(locations[0].points.count == 2)
        #expect(locations[1].points.count == 1)
        // Sorted ascending by day.
        #expect(locations[0].day < locations[1].day)
        // The New York point never lands in the California grouping.
        #expect(!locations.flatMap(\.points).map(\.coordinate).contains(Coordinate(
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
        #expect(other[0].points.count == 1)

        let california = aggregator.locations(
            in: .california,
            samples: samples,
            attributor: attributor,
        )
        #expect(california.isEmpty)
    }

    @Test func locationsCarryHorizontalAccuracy() {
        // The fix's horizontal accuracy must survive aggregation so the map can
        // draw a GPS uncertainty radius around the point.
        let samples = [
            makeSample(at: "2026-05-01T09:00:00-07:00", lat: 37.7749, lng: -122.4194, accuracy: 65),
        ]
        let locations = aggregator.locations(
            in: .california,
            samples: samples,
            attributor: attributor,
        )
        #expect(locations.count == 1)
        #expect(locations[0].points.first?.horizontalAccuracy == 65)
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

    @Test func pointsByRegionGroupsOneDayAcrossRegions() {
        // A same-day flight: two CA points, an .other fly-over, and an NY point.
        let samples = [
            makeSample(at: "2026-07-14T08:00:00-07:00", lat: 37.6213, lng: -122.3790), // CA
            makeSample(at: "2026-07-14T10:00:00-07:00", lat: 37.7749, lng: -122.4194), // CA
            makeSample(at: "2026-07-14T13:00:00-07:00", lat: 39.53, lng: -106.16), // .other
            makeSample(at: "2026-07-14T17:00:00-07:00", lat: 40.7128, lng: -74.0060), // NY
        ]
        let byRegion = aggregator.pointsByRegion(
            onDay: CalendarDay(year: 2026, month: 7, day: 14),
            samples: samples,
            attributor: attributor,
        )
        #expect(byRegion[.california]?.count == 2)
        #expect(byRegion[.other]?.count == 1)
        #expect(byRegion[.newYork]?.count == 1)
        #expect(byRegion[.canada] == nil)
    }

    @Test func pointsByRegionExcludesOtherDays() {
        let samples = [
            makeSample(at: "2026-07-14T10:00:00-07:00", lat: 37.7749, lng: -122.4194),
            makeSample(at: "2026-07-15T10:00:00-07:00", lat: 37.7749, lng: -122.4194),
        ]
        let byRegion = aggregator.pointsByRegion(
            onDay: CalendarDay(year: 2026, month: 7, day: 14),
            samples: samples,
            attributor: attributor,
        )
        #expect(byRegion[.california]?.count == 1)
    }

    @Test func pointsByRegionCarryHorizontalAccuracy() {
        let samples = [
            makeSample(at: "2026-07-14T10:00:00-07:00", lat: 37.7749, lng: -122.4194, accuracy: 42),
        ]
        let byRegion = aggregator.pointsByRegion(
            onDay: CalendarDay(year: 2026, month: 7, day: 14),
            samples: samples,
            attributor: attributor,
        )
        #expect(byRegion[.california]?.first?.horizontalAccuracy == 42)
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

    private func makeSample(
        at iso: String,
        lat: Double,
        lng: Double,
        accuracy: Double = 0,
    ) -> LocationSample {
        let formatter = ISO8601DateFormatter()
        return LocationSample(
            timestamp: formatter.date(from: iso) ?? Date(timeIntervalSince1970: 0),
            coordinate: Coordinate(latitude: lat, longitude: lng),
            horizontalAccuracy: accuracy,
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
