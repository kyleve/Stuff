import Foundation
import RegionKit
import Testing
import WhereCore

private typealias Fixtures = DataIssueDetectorFixtures

struct BorderDriftDetectorTests {
    @Test func flagsNearbyOtherDay() {
        let otherDay = DayPresence(date: Fixtures.day(2026, 3, 1), regions: [.other])
        // Reno — outside CA but close to the border.
        let reno = Coordinate(latitude: 39.5296, longitude: -119.8138)
        let issues = BorderDriftDetector().detectIssues(in: Fixtures.input(
            days: [otherDay],
            otherDayCoordinates: [otherDay.date: [reno]],
            driftThresholdMeters: 50000,
        ))
        #expect(issues.count == 1)
        #expect(issues[0].nearestRegion == .california)
        #expect(issues[0].distanceMeters <= 50000)
        // A pure-.other day has no real region left, so it suggests the nearest.
        guard case let .relabelDay(_, suggested, _) = issues[0].resolution else {
            Issue.record("expected relabelDay resolution")
            return
        }
        #expect(suggested == [.california])
    }

    @Test func flagsMixedDayWithStrayOther() {
        // A day that already counts for California but picked up a stray .other.
        let mixedDay = DayPresence(date: Fixtures.day(2026, 3, 1), regions: [.california, .other])
        let reno = Coordinate(latitude: 39.5296, longitude: -119.8138)
        let issues = BorderDriftDetector().detectIssues(in: Fixtures.input(
            days: [mixedDay],
            otherDayCoordinates: [mixedDay.date: [reno]],
            driftThresholdMeters: 50000,
        ))
        #expect(issues.count == 1)
        #expect(issues[0].nearestRegion == .california)
        // The fix keeps the real region and drops only the spurious .other.
        guard case let .relabelDay(_, suggested, _) = issues[0].resolution else {
            Issue.record("expected relabelDay resolution")
            return
        }
        #expect(suggested == [.california])
    }

    @Test func flagsManhattanRiverDriftLikeJune26() {
        // Real-world regression: a New York day whose only .other coordinates
        // are the two coarse June 26 fixes that drifted west toward the Hudson
        // (~852 m / ~952 m outside the NY polygon), checked at the 1 km default.
        let day = DayPresence(date: Fixtures.day(2026, 6, 26), regions: [.newYork, .other])
        let strayPoints = [
            Coordinate(latitude: 40.80015, longitude: -73.99439),
            Coordinate(latitude: 40.81084, longitude: -73.98805),
        ]
        let issues = BorderDriftDetector().detectIssues(in: Fixtures.input(
            days: [day],
            otherDayCoordinates: [day.date: strayPoints],
            driftThresholdMeters: DriftThreshold.km1.meters,
        ))
        #expect(issues.count == 1)
        #expect(issues[0].nearestRegion == .newYork)
        #expect(issues[0].distanceMeters < DriftThreshold.km1.meters)
        guard case let .relabelDay(_, suggested, _) = issues[0].resolution else {
            Issue.record("expected relabelDay resolution")
            return
        }
        #expect(suggested == [.newYork]) // the spurious .other is dropped
    }

    @Test func skipsWhenBeyondThreshold() {
        let otherDay = DayPresence(date: Fixtures.day(2026, 3, 1), regions: [.other])
        let tokyo = Coordinate(latitude: 35.6762, longitude: 139.6503)
        let issues = BorderDriftDetector().detectIssues(in: Fixtures.input(
            days: [otherDay],
            otherDayCoordinates: [otherDay.date: [tokyo]],
        ))
        #expect(issues.isEmpty)
    }

    @Test func skipsAttributedRegion() {
        let caDay = DayPresence(date: Fixtures.day(2026, 3, 1), regions: [.california])
        let sf = Coordinate(latitude: 37.7749, longitude: -122.4194)
        let issues = BorderDriftDetector().detectIssues(in: Fixtures.input(
            days: [caDay],
            otherDayCoordinates: [caDay.date: [sf]],
        ))
        #expect(issues.isEmpty)
    }
}
