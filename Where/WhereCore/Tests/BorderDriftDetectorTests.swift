import Foundation
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
