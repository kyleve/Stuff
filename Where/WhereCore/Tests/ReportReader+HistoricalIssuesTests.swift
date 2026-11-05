import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct ReportReaderHistoricalIssuesTests {
    @Test func readsStoredYearsAndCurrentYearWithTheirOriginalQueries() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        try await LocationHistoryReaderTestSupport.add(
            [LocationHistoryReaderTestSupport.sample(seconds: 0)],
            to: store,
        )
        try await store.perform {
            try await store.setManualDay(.init(
                day: .init(year: 1999, month: 7, day: 1),
                regions: [.california],
            ))
        }
        let result = try await LocationHistoryReaderTestSupport.reports(store)
            .historicalDataIssueReads(currentYear: 2002)
        #expect(result.years.map(\.context.historicalYear) == [1999, 2001, 2002])
        #expect(result.years.map(\.reads.dataGenerationID) == Array(
            repeating: result.generationID,
            count: 3,
        ))
        #expect(result.years.first?.context.query == .days(
            CalendarDay(year: 1998, month: 12, day: 31)
                ... CalendarDay(year: 2000, month: 1, day: 1),
        ))
    }

    @Test(arguments: [1, 9999])
    func supportedBoundaryYearsDoNotRequestUnsupportedAdjacentDates(year: Int) async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let result = try await LocationHistoryReaderTestSupport.reports(store)
            .historicalDataIssueReads(currentYear: year)
        #expect(result.years.map(\.reads.report.year) == [year])
        let query = try #require(result.years.first?.context.query)
        if case let .days(days) = query {
            #expect((1 ... 9999).contains(days.lowerBound.year))
            #expect((1 ... 9999).contains(days.upperBound.year))
        } else {
            Issue.record("Expected an explicit logical-date query")
        }
    }

    @Test(arguments: [0, 10000])
    func unsupportedCurrentYearFailsBeforeReading(year: Int) async throws {
        let store = try await RecordingChoiceTestSupport.store()
        await #expect(throws: HistoryYearInventory.ValidationError.unsupportedDate) {
            try await LocationHistoryReaderTestSupport.reports(store)
                .historicalDataIssueReads(currentYear: year)
        }
    }
}
