import Foundation
import Testing
@testable import WhereCore

struct HistoryYearInventoryTests {
    @Test func knownLogicalDatesDoNotAddPossibleNeighboringYears() throws {
        var inventory = HistoryYearInventory()
        try inventory.include(day: CalendarDay(year: 2000, month: 12, day: 31))
        #expect(inventory.years == [2000])
    }

    @Test func unknownTimestampIncludesBothExtremeOffsetsAtANewYearBoundary() throws {
        var inventory = HistoryYearInventory()
        // UTC December 31 at 06:00 is January 1 at the largest supported positive offset.
        try inventory.includePossibleYears(at: RecordingAssessmentTestSupport.time(-18 * 3600))
        #expect(inventory.years == [2000, 2001])
    }

    @Test func halfOpenPeriodExcludesAnExactYearBoundaryButPreservesSubsecondCoverage() throws {
        let boundary = -18.0 * 3600
        var ending = HistoryYearInventory()
        try ending.includePossibleYears(in: RecordingAssessmentTestSupport.period(
            boundary - 1,
            boundary,
        ))
        #expect(ending.years == [2000])
        var crossing = HistoryYearInventory()
        try crossing.includePossibleYears(in: RecordingAssessmentTestSupport.period(
            boundary - 0.5,
            boundary + 0.5,
        ))
        #expect(crossing.years == [2000, 2001])
    }

    @Test func periodInventoryIncludesEveryIntermediateYear() throws {
        var inventory = HistoryYearInventory()
        try inventory.includePossibleYears(in: RecordingPeriod(
            start: WhereCoreTestSupport.iso("1998-07-01T12:00:00Z"),
            end: WhereCoreTestSupport.iso("2002-07-01T12:00:00Z"),
        ))
        #expect(inventory.years == [1998, 1999, 2000, 2001, 2002])
    }

    @Test func timestampsUseTheExplicitViewingCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: -3600))
        var inventory = HistoryYearInventory()
        try inventory.include(timestamp: RecordingAssessmentTestSupport.time(0), calendar: calendar)
        #expect(inventory.years == [2000])
    }

    @Test func unsupportedDatesFailInsteadOfProducingAnEmptyInventory() throws {
        var inventory = HistoryYearInventory()
        #expect(throws: HistoryYearInventory.ValidationError.unsupportedDate) {
            try inventory.include(day: CalendarDay(year: 2001, month: 2, day: 30))
        }
        #expect(throws: HistoryYearInventory.ValidationError.unsupportedDate) {
            try inventory.includePossibleYears(at: Date(timeIntervalSinceReferenceDate: .infinity))
        }
        let invalid = try JSONDecoder().decode(
            RecordingPeriod.self,
            from: Data(#"{"start":20,"end":10}"#.utf8),
        )
        #expect(throws: RecordingPeriod.ValidationError.self) {
            try inventory.includePossibleYears(in: invalid)
        }
    }

    @Test func possibleYearsAtTheSupportedEraBoundaryNeverInventABCEHistoryYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let date = try #require(calendar.date(from: DateComponents(year: 1, month: 1, day: 1)))
        var inventory = HistoryYearInventory()
        try inventory.includePossibleYears(at: date)
        #expect(inventory.years == [1])
    }
}
