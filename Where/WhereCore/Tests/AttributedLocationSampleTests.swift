import Foundation
import Testing
@testable import WhereCore

struct AttributedLocationSampleTests {
    @Test func effectiveDaySurvivesRegionChangesWithoutRewritingRawContext() throws {
        let sample = try #require(RecordingBackupTestSupport.convertedArchive().samples.first)
        let day = CalendarDay(year: 2000, month: 12, day: 31)
        let entry = AttributedLocationSample(
            sample: sample,
            regions: [.california],
            day: .recording(day),
        )
        let changed = entry.replacingRegions([.other])
        #expect(changed.day == .recording(day))
        #expect(changed.sample == sample)
        #expect(changed.regions == [.other])
        #expect(entry.regions == [.california])
    }

    @Test func foundationConstructionKeepsViewingCalendarSemantics() throws {
        let sample = try #require(RecordingBackupTestSupport.convertedArchive().samples.first)
        let entry = AttributedLocationSample(sample: sample, regions: [.california])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        #expect(entry.day == .viewingCalendar)
        #expect(entry.calendarDay(in: calendar) == CalendarDay(
            from: sample.timestamp,
            in: calendar,
        ))
    }

    @Test func reportingGroupsOnlySelectedGPSAndPreservesManualAssertions() throws {
        let day = CalendarDay(year: 2025, month: 12, day: 31)
        let gps = try #require(RecordingBackupTestSupport.convertedArchive().samples.first)
        let entry = AttributedLocationSample(sample: gps, regions: [.newYork], day: .recording(day))
        let grouped = entry.reporting(primaryRegions: [.california])
        #expect(grouped.regions == [.other])
        #expect(grouped.day == .recording(day))
        #expect(grouped.sample == gps)
        #expect(entry.regions == [.newYork])
        #expect(entry.replacingRegions([]).reporting(primaryRegions: []).regions.isEmpty)

        let manual = FlightTrajectoryFixtures.sample(999, minutes: 0, east: 0, source: .manual)
        let assertion = AttributedLocationSample(sample: manual, regions: [.newYork])
        #expect(assertion.reporting(primaryRegions: []) == assertion)
        let foundation = AttributedLocationSample(sample: gps, regions: [.newYork])
        #expect(foundation.reporting(primaryRegions: []) == foundation)
    }
}
