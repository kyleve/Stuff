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
}
