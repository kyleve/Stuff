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
        let date = Fixtures.day(2026, 7, 14)
        let day = DayPresence(date: date, regions: [.newYork, .other, .california])
        let samples = [
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 8.0, Self.jfk),
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 8.5, Self.jfk),
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 12.0, Self.jfk),
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 13.5, Self.illinois),
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 15.0, Self.colorado),
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 16.5, Self.nevada),
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 17.5, Self.sfo),
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 18.0, Self.sfo),
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

    /// A flight with a genuine layover in an untracked region: even with two
    /// fly-over `.other` fixes, a real `.other` stop (dwell fixes in Chicago)
    /// keeps `.other` grounded, so nothing is removed and the day isn't flagged.
    /// The detector must not strip a region the user actually stopped in.
    @Test func keepsRegionWithALegitimateLayover() {
        let date = Fixtures.day(2026, 7, 14)
        let chicago = Coordinate(latitude: 41.8781, longitude: -87.6298) // .other, with dwell
        let day = DayPresence(date: date, regions: [.newYork, .other, .california])
        let samples = [
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 8.0, Self.jfk),
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 9.0, Self.jfk),
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 11.0, Self.colorado), // fly-over
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 12.5, Self.nevada), // fly-over
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 14.0, chicago), // land + dwell
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 15.0, chicago),
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 16.0, chicago),
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 19.0, Self.sfo),
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
        let date = Fixtures.day(2026, 7, 14)
        let day = DayPresence(date: date, regions: [.newYork, .other])
        let newYorkCity = Coordinate(latitude: 40.7128, longitude: -74.0060)
        let newJersey = Coordinate(latitude: 40.05, longitude: -74.60) // .other, ~80 km away
        let samples = [
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 9.0, newYorkCity),
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 10.0, newJersey),
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 11.0, newYorkCity),
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
        let date = Fixtures.day(2026, 7, 14)
        let day = DayPresence(date: date, regions: [.newYork, .other])
        let samples = [
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 9.0, Self.jfk),
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 9.05, Self.colorado),
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 9.1, Self.jfk),
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
        let date = Fixtures.day(2026, 7, 14)
        let day = DayPresence(date: date, regions: [.other])
        let samples = [
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 0.5, Self.illinois),
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 2.0, Self.colorado),
            Fixtures.gpsSample(dayStart: date, hoursAfterStart: 3.5, Self.nevada),
        ]
        let issues = FlightDayDetector().detectIssues(in: Fixtures.input(
            days: [day],
            daySamples: [date: samples],
        ))
        #expect(issues.isEmpty)
    }

    @Test func skipsDayWithNoSamples() {
        let date = Fixtures.day(2026, 7, 14)
        let day = DayPresence(date: date, regions: [.newYork, .other, .california])
        let issues = FlightDayDetector().detectIssues(in: Fixtures.input(days: [day]))
        #expect(issues.isEmpty)
    }
}
