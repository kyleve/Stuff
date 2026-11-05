import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct HistoryReportCSVTests {
    @Test func logicalDatesAndSpecificRegionsRemainStableAcrossOrdering() throws {
        let first = CalendarDay(year: 2026, month: 1, day: 1)
        let second = CalendarDay(year: 2026, month: 12, day: 31)
        let report = YearReport(
            year: 2026,
            days: [
                .init(day: second, regions: [.newYork]),
                .init(day: first, regions: [.newYork, .california]),
            ],
            totals: [.california: 1, .newYork: 2],
        )
        let document = try HistoryReportCSV(report: report)
        let expected = "calendar_day,region_id,region_name\r\n" +
            "2026-01-01,us-CA,\(Region.california.localizedName)\r\n" +
            "2026-01-01,us-NY,\(Region.newYork.localizedName)\r\n" +
            "2026-12-31,us-NY,\(Region.newYork.localizedName)\r\n"
        #expect(document.year == 2026)
        #expect(document.data == Data(expected.utf8))
    }

    @Test func completeEmptyHistoryProducesOnlyTheHeader() throws {
        let document = try HistoryReportCSV(report: .init(year: 2026, days: [], totals: [:]))
        #expect(document.data == Data("calendar_day,region_id,region_name\r\n".utf8))
    }

    @Test(arguments: [
        ["Côte d’Ivoire", "Côte d’Ivoire"],
        ["Bonaire, Sint Eustatius and Saba", "\"Bonaire, Sint Eustatius and Saba\""],
        ["A \"quoted\" name", "\"A \"\"quoted\"\" name\""],
        ["Two\r\nlines", "\"Two\r\nlines\""],
        ["Two\nlines", "\"Two\nlines\""],
        ["Two\rlines", "\"Two\rlines\""],
    ])
    func fieldsPreserveUnicodeAndEscapeCSVBoundaries(_ example: [String]) {
        #expect(HistoryReportCSV.field(example[0]) == example[1])
    }

    @Test func unresolvedReportsCannotBeEncodedEvenIfTheyHaveResolvedTotals() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let samples = try LocationHistoryReaderTestSupport.competingTracks()
        let resolved = try LocationHistoryReaderTestSupport.sample(seconds: 7200)
        try await LocationHistoryReaderTestSupport.add(samples + [resolved], to: store)
        let report = try await LocationHistoryReaderTestSupport.reports(store).yearReport(for: 2001)
        #expect(!report.completeness.isComplete)
        #expect(report.totals[.california] == 1)
        #expect(throws: UnresolvedHistoryError.self) { try HistoryReportCSV(report: report) }
    }
}
