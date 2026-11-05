import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct ReportReaderHistoryInventoryTests {
    @Test func combinesActualGPSManualAndEvidenceYearsWithoutAddingTheCurrentYear() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        try await LocationHistoryReaderTestSupport.add(
            [LocationHistoryReaderTestSupport.sample(seconds: 0)],
            to: store,
        )
        try await store.perform {
            try await store.setManualDay(DayPresence(
                day: CalendarDay(year: 1997, month: 7, day: 1),
                regions: [.california],
            ))
            try await store.write(evidence: Evidence(
                kind: .document,
                capturedAt: WhereCoreTestSupport.iso("1999-07-01T12:00:00Z"),
                contentType: .plainText,
            ), blob: nil)
        }
        let reader = LocationHistoryReaderTestSupport.reports(store)
        #expect(try await reader.historyYears() == [1997, 1999, 2001])
        #expect(try await store.allSamples().count == 1)
    }

    @Test func emptyHistoryHasNoStoredYears() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        #expect(try await LocationHistoryReaderTestSupport.reports(store).historyYears().isEmpty)
    }
}
