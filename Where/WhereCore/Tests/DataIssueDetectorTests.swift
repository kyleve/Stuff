import Foundation
import Testing
import WhereCore

struct DataIssueDetectorTests {
    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.startOfDay(for: calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
        ))!)
    }

    private static func input(
        year: Int = 2026,
        days: [DayPresence] = [],
        otherDayCoordinates: [Date: [Coordinate]] = [:],
        primaryRegions: [Region] = [.california, .newYork],
        driftThresholdMeters: Double = 10000,
        now: Date? = nil,
    ) -> DataIssueInput {
        let totals = Dictionary(grouping: days.flatMap(\.regions), by: { $0 }).mapValues(\.count)
        return DataIssueInput(
            year: year,
            report: YearReport(year: year, days: days, totals: totals),
            otherDayCoordinates: otherDayCoordinates,
            primaryRegions: primaryRegions,
            attributor: .shared,
            driftThresholdMeters: driftThresholdMeters,
            calendar: calendar,
            now: now ?? day(year, 6, 15),
        )
    }

    // MARK: - MissingDaysDetector

    @Test func missingDaysDetector_currentYearUsesBacklogCutoff() {
        let present: [DayPresence] = [
            DayPresence(date: Self.day(2026, 1, 1), regions: [.california]),
        ]
        let now = Self.day(2026, 1, 5)
        let issues = MissingDaysDetector().detectIssues(in: Self.input(
            year: 2026,
            days: present,
            now: now,
        ))
        #expect(issues.count == 1)
        #expect(issues[0].range.start == Self.day(2026, 1, 2))
        #expect(issues[0].range.end == Self.day(2026, 1, 4))
        #expect(issues[0].range.dayCount == 3)
        #expect(issues[0].isDismissible == false)
    }

    @Test func missingDaysDetector_futureYearReturnsEmpty() {
        // A year that hasn't started yet must not report every day as missing.
        let issues = MissingDaysDetector().detectIssues(in: Self.input(
            year: 2027,
            days: [],
            now: Self.day(2026, 6, 15),
        ))
        #expect(issues.isEmpty)
    }

    @Test func missingDaysDetector_pastYearThroughDec31() {
        let present: [DayPresence] = [
            DayPresence(date: Self.day(2025, 12, 30), regions: [.california]),
        ]
        let issues = MissingDaysDetector().detectIssues(in: Self.input(
            year: 2025,
            days: present,
            now: Self.day(2026, 6, 15),
        ))
        #expect(issues.contains { $0.range.start == Self.day(2025, 12, 31) })
    }

    // MARK: - BorderDriftDetector

    @Test func borderDriftDetector_flagsNearbyOtherDay() {
        let otherDay = DayPresence(date: Self.day(2026, 3, 1), regions: [.other])
        // Reno — outside CA but close to the border.
        let reno = Coordinate(latitude: 39.5296, longitude: -119.8138)
        let issues = BorderDriftDetector().detectIssues(in: Self.input(
            days: [otherDay],
            otherDayCoordinates: [otherDay.date: [reno]],
            driftThresholdMeters: 50000,
        ))
        #expect(issues.count == 1)
        #expect(issues[0].nearestRegion == .california)
        #expect(issues[0].distanceMeters <= 50000)
    }

    @Test func borderDriftDetector_skipsWhenBeyondThreshold() {
        let otherDay = DayPresence(date: Self.day(2026, 3, 1), regions: [.other])
        let tokyo = Coordinate(latitude: 35.6762, longitude: 139.6503)
        let issues = BorderDriftDetector().detectIssues(in: Self.input(
            days: [otherDay],
            otherDayCoordinates: [otherDay.date: [tokyo]],
        ))
        #expect(issues.isEmpty)
    }

    @Test func borderDriftDetector_skipsAttributedRegion() {
        let caDay = DayPresence(date: Self.day(2026, 3, 1), regions: [.california])
        let sf = Coordinate(latitude: 37.7749, longitude: -122.4194)
        let issues = BorderDriftDetector().detectIssues(in: Self.input(
            days: [caDay],
            otherDayCoordinates: [caDay.date: [sf]],
        ))
        #expect(issues.isEmpty)
    }

    // MARK: - AbruptLocationChangeDetector

    @Test func abruptChangeDetector_flagsAdjacentDisjointDays() {
        let earlier = DayPresence(date: Self.day(2026, 4, 10), regions: [.california])
        let later = DayPresence(date: Self.day(2026, 4, 11), regions: [.newYork])
        let issues = AbruptLocationChangeDetector().detectIssues(in: Self.input(days: [
            earlier,
            later,
        ]))
        #expect(issues.count == 1)
        #expect(issues[0].earlierDay == earlier)
        #expect(issues[0].laterDay == later)
        if case let .markTravelDay(e, l, suggested) = issues[0].resolution {
            #expect(e == earlier)
            #expect(l == later)
            #expect(suggested == [.california, .newYork])
        } else {
            Issue.record("Expected markTravelDay resolution")
        }
    }

    @Test func abruptChangeDetector_skipsOverlappingRegions() {
        let earlier = DayPresence(date: Self.day(2026, 4, 10), regions: [.california, .newYork])
        let later = DayPresence(date: Self.day(2026, 4, 11), regions: [.newYork])
        let issues = AbruptLocationChangeDetector().detectIssues(in: Self.input(days: [
            earlier,
            later,
        ]))
        #expect(issues.isEmpty)
    }

    @Test func abruptChangeDetector_skipsGapInCalendar() {
        let earlier = DayPresence(date: Self.day(2026, 4, 10), regions: [.california])
        let later = DayPresence(date: Self.day(2026, 4, 12), regions: [.newYork])
        let issues = AbruptLocationChangeDetector().detectIssues(in: Self.input(days: [
            earlier,
            later,
        ]))
        #expect(issues.isEmpty)
    }

    // MARK: - Type erasure

    @Test func detectAnyIssues_erasesToExistential() {
        let detector: any DataIssueDetecting = MissingDaysDetector()
        let issues = detector.detectAnyIssues(in: Self.input())
        #expect(!issues.isEmpty)
        #expect(issues.allSatisfy { $0.category == .missingDays })
    }
}
