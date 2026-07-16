import Foundation
import RegionKit
import Testing
import WhereCore

private typealias Fixtures = DataIssueDetectorFixtures

struct FlightDayDetectorTests {
    // Real coordinates the shared attributor resolves as expected.
    private static let jfk = Coordinate(latitude: 40.6413, longitude: -73.7781) // New York
    private static let sfo = Coordinate(latitude: 37.6213, longitude: -122.3790) // California
    private static let illinois = Coordinate(latitude: 40.29, longitude: -90.39) // .other
    private static let colorado = Coordinate(latitude: 39.53, longitude: -106.16) // .other
    private static let nevada = Coordinate(latitude: 38.68, longitude: -116.90) // .other

    /// The July 14 NYC→SF profile: two grounded NY fixes in the morning, a run
    /// of cruise-speed legs across untracked states, then grounded SFO fixes.
    @Test func flagsCoastToCoastFlight() {
        let date = Fixtures.calendarDay(2026, 7, 14)
        let day = DayPresence(day: date, regions: [.newYork, .other, .california])
        let samples = [
            Fixtures.gpsSample(day: date, hoursAfterStart: 8.0, Self.jfk),
            Fixtures.gpsSample(day: date, hoursAfterStart: 8.5, Self.jfk),
            Fixtures.gpsSample(day: date, hoursAfterStart: 12.0, Self.jfk),
            Fixtures.gpsSample(day: date, hoursAfterStart: 13.5, Self.illinois),
            Fixtures.gpsSample(day: date, hoursAfterStart: 15.0, Self.colorado),
            Fixtures.gpsSample(day: date, hoursAfterStart: 16.5, Self.nevada),
            Fixtures.gpsSample(day: date, hoursAfterStart: 17.5, Self.sfo),
            Fixtures.gpsSample(day: date, hoursAfterStart: 18.0, Self.sfo),
        ]
        let issues = FlightDayDetector().detectIssues(in: Fixtures.input(
            days: [day],
            daySamples: [date: samples],
        ))

        #expect(issues.count == 1)
        #expect(issues[0].keepRegions == [.newYork, .california])
        #expect(issues[0].removedRegions == [.other])
        #expect(issues[0].peakSpeedKMH > 300)
        guard case let .correctFlightDay(d, keep, removed, peak) = issues[0].resolution else {
            Issue.record("expected correctFlightDay resolution")
            return
        }
        #expect(d == day)
        #expect(keep == [.newYork, .california])
        #expect(removed == [.other])
        #expect(peak > 300)
    }

    /// Real-world regression (the July 14 export that didn't flag): CoreLocation
    /// emits a Visit *and* a significant-change fix at the same instant, so a
    /// mid-cruise waypoint has an exact-timestamp duplicate. The zero-duration
    /// leg between them must not make that cruise fix read as "grounded" — the
    /// day should still flag with `.other` removed.
    @Test func flagsFlightWithDuplicateMidCruiseFixes() {
        let date = Fixtures.calendarDay(2026, 7, 14)
        let day = DayPresence(day: date, regions: [.newYork, .other, .california])
        let samples = [
            Fixtures.gpsSample(day: date, hoursAfterStart: 8.0, Self.jfk),
            Fixtures.gpsSample(day: date, hoursAfterStart: 8.5, Self.jfk),
            Fixtures.gpsSample(day: date, hoursAfterStart: 12.0, Self.jfk),
            Fixtures.gpsSample(day: date, hoursAfterStart: 13.5, Self.illinois),
            // A Visit + significant-change at the same instant, mid-cruise.
            Fixtures.gpsSample(day: date, hoursAfterStart: 15.0, Self.colorado, source: .gpsVisit),
            Fixtures.gpsSample(day: date, hoursAfterStart: 15.0, Self.colorado),
            Fixtures.gpsSample(day: date, hoursAfterStart: 16.5, Self.nevada, source: .gpsVisit),
            Fixtures.gpsSample(day: date, hoursAfterStart: 16.5, Self.nevada),
            Fixtures.gpsSample(day: date, hoursAfterStart: 17.5, Self.sfo),
            Fixtures.gpsSample(day: date, hoursAfterStart: 18.0, Self.sfo),
        ]
        let issues = FlightDayDetector().detectIssues(in: Fixtures.input(
            days: [day],
            daySamples: [date: samples],
        ))
        #expect(issues.count == 1)
        #expect(issues[0].keepRegions == [.newYork, .california])
        #expect(issues[0].removedRegions == [.other])
    }

    /// Real-world regression (the July 14 export that didn't flag): at cruise,
    /// significant-change fires every ~5 min, so each leg is only ~70 km even
    /// though it's minutes long. Those legs must still count as flight (a
    /// distance floor would wrongly drop them and leave the fly-over region
    /// looking grounded), so a densely-sampled cruise still flags.
    @Test func flagsDenselySampledCruise() {
        let date = Fixtures.calendarDay(2026, 7, 14)
        let day = DayPresence(day: date, regions: [.newYork, .other, .california])
        // Untracked mid-continent waypoints ~70 km / 6 min apart (~700 km/h).
        let a = Coordinate(latitude: 38.5, longitude: -100.0)
        let b = Coordinate(latitude: 38.5, longitude: -100.8)
        let c = Coordinate(latitude: 38.5, longitude: -101.6)
        let d = Coordinate(latitude: 38.5, longitude: -102.4)
        let samples = [
            Fixtures.gpsSample(day: date, hoursAfterStart: 8.0, Self.jfk),
            Fixtures.gpsSample(day: date, hoursAfterStart: 8.5, Self.jfk),
            Fixtures.gpsSample(day: date, hoursAfterStart: 9.0, a),
            Fixtures.gpsSample(day: date, hoursAfterStart: 9.1, b),
            Fixtures.gpsSample(day: date, hoursAfterStart: 9.2, c),
            Fixtures.gpsSample(day: date, hoursAfterStart: 9.3, d),
            Fixtures.gpsSample(day: date, hoursAfterStart: 10.0, Self.sfo),
            Fixtures.gpsSample(day: date, hoursAfterStart: 10.5, Self.sfo),
        ]
        let issues = FlightDayDetector().detectIssues(in: Fixtures.input(
            days: [day],
            daySamples: [date: samples],
        ))
        #expect(issues.count == 1)
        #expect(issues[0].keepRegions == [.newYork, .california])
        #expect(issues[0].removedRegions == [.other])
    }

    /// A flight with a genuine layover in an untracked region: even with two
    /// fly-over `.other` fixes, a real `.other` stop (dwell fixes in Chicago)
    /// keeps `.other` grounded, so nothing is removed and the day isn't flagged.
    /// The detector must not strip a region the user actually stopped in.
    @Test func keepsRegionWithALegitimateLayover() {
        let date = Fixtures.calendarDay(2026, 7, 14)
        let chicago = Coordinate(latitude: 41.8781, longitude: -87.6298) // .other, with dwell
        let day = DayPresence(day: date, regions: [.newYork, .other, .california])
        let samples = [
            Fixtures.gpsSample(day: date, hoursAfterStart: 8.0, Self.jfk),
            Fixtures.gpsSample(day: date, hoursAfterStart: 9.0, Self.jfk),
            Fixtures.gpsSample(day: date, hoursAfterStart: 11.0, Self.colorado), // fly-over
            Fixtures.gpsSample(day: date, hoursAfterStart: 12.5, Self.nevada), // fly-over
            Fixtures.gpsSample(day: date, hoursAfterStart: 14.0, chicago), // land + dwell
            Fixtures.gpsSample(day: date, hoursAfterStart: 15.0, chicago),
            Fixtures.gpsSample(day: date, hoursAfterStart: 16.0, chicago),
            Fixtures.gpsSample(day: date, hoursAfterStart: 19.0, Self.sfo),
        ]
        let issues = FlightDayDetector().detectIssues(in: Fixtures.input(
            days: [day],
            daySamples: [date: samples],
        ))
        #expect(issues.isEmpty)
    }

    /// A fast road trip that dips into `.other` but never reaches cruise speed:
    /// no leg clears the threshold, so nothing is a fly-over point.
    @Test func ignoresFastDrivingBelowThreshold() {
        let date = Fixtures.calendarDay(2026, 7, 14)
        let day = DayPresence(day: date, regions: [.newYork, .other])
        let newYorkCity = Coordinate(latitude: 40.7128, longitude: -74.0060)
        let newJersey = Coordinate(latitude: 40.05, longitude: -74.60) // .other, ~80 km away
        let samples = [
            Fixtures.gpsSample(day: date, hoursAfterStart: 9.0, newYorkCity),
            Fixtures.gpsSample(day: date, hoursAfterStart: 10.0, newJersey),
            Fixtures.gpsSample(day: date, hoursAfterStart: 11.0, newYorkCity),
        ]
        let issues = FlightDayDetector().detectIssues(in: Fixtures.input(
            days: [day],
            daySamples: [date: samples],
        ))
        #expect(issues.isEmpty)
    }

    /// A single teleport glitch — one bad fix that jumps far away and straight
    /// back — is a different data issue, not a plane, so it isn't flagged.
    @Test func ignoresLoneTeleportGlitch() {
        let date = Fixtures.calendarDay(2026, 7, 14)
        let day = DayPresence(day: date, regions: [.newYork, .other])
        let samples = [
            Fixtures.gpsSample(day: date, hoursAfterStart: 9.0, Self.jfk),
            Fixtures.gpsSample(day: date, hoursAfterStart: 9.05, Self.colorado),
            Fixtures.gpsSample(day: date, hoursAfterStart: 9.1, Self.jfk),
        ]
        let issues = FlightDayDetector().detectIssues(in: Fixtures.input(
            days: [day],
            daySamples: [date: samples],
        ))
        #expect(issues.isEmpty)
    }

    /// A day spent entirely mid-cruise (no grounded endpoint on this calendar
    /// day) leaves the crossed region grounded at its first/last fix, so there
    /// is nothing spurious to remove — the day is left alone, not blanked.
    @Test func skipsMidFlightOnlyDay() {
        let date = Fixtures.calendarDay(2026, 7, 14)
        let day = DayPresence(day: date, regions: [.other])
        let samples = [
            Fixtures.gpsSample(day: date, hoursAfterStart: 0.5, Self.illinois),
            Fixtures.gpsSample(day: date, hoursAfterStart: 2.0, Self.colorado),
            Fixtures.gpsSample(day: date, hoursAfterStart: 3.5, Self.nevada),
        ]
        let issues = FlightDayDetector().detectIssues(in: Fixtures.input(
            days: [day],
            daySamples: [date: samples],
        ))
        #expect(issues.isEmpty)
    }

    @Test func skipsDayWithNoSamples() {
        let date = Fixtures.calendarDay(2026, 7, 14)
        let day = DayPresence(day: date, regions: [.newYork, .other, .california])
        let issues = FlightDayDetector().detectIssues(in: Fixtures.input(days: [day]))
        #expect(issues.isEmpty)
    }
}
