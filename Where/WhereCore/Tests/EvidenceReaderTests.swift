import Foundation
import Testing
@testable import WhereCore

struct EvidenceReaderTests {
    private static let aggregator = DayAggregator()

    private static func evidence(on date: Date, note: String) -> Evidence {
        Evidence(
            kind: .document,
            capturedAt: date,
            note: note,
            contentType: .pdf,
        )
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        aggregator.calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour),
        )!
    }

    @Test func list_returnsEvidenceInSelectedYearOnly() async throws {
        let store = try SwiftDataStore.inMemory()
        let reader = EvidenceReader(store: store, aggregator: Self.aggregator)
        let inYear = Self.evidence(on: Self.date(2026, 3, 4), note: "in")
        let priorYear = Self.evidence(on: Self.date(2025, 12, 31), note: "out")
        try await store.perform {
            try await store.write(evidence: inYear, blob: nil)
            try await store.write(evidence: priorYear, blob: nil)
        }

        let list = try await reader.list(for: 2026)
        #expect(list.map(\.id) == [inYear.id])
    }

    @Test func dayKeys_collapsesMultipleEvidencePerDay() async throws {
        let store = try SwiftDataStore.inMemory()
        let reader = EvidenceReader(store: store, aggregator: Self.aggregator)
        // Two on the same day, one on another — expect two distinct day keys.
        let morning = Self.evidence(on: Self.date(2026, 3, 4, hour: 8), note: "am")
        let evening = Self.evidence(on: Self.date(2026, 3, 4, hour: 20), note: "pm")
        let otherDay = Self.evidence(on: Self.date(2026, 7, 9), note: "other")
        try await store.perform {
            try await store.write(evidence: morning, blob: nil)
            try await store.write(evidence: evening, blob: nil)
            try await store.write(evidence: otherDay, blob: nil)
        }

        let keys = try await reader.dayKeys(for: 2026)
        let expected: Set<CalendarDay> = [
            CalendarDay(year: 2026, month: 3, day: 4),
            CalendarDay(year: 2026, month: 7, day: 9),
        ]
        #expect(keys == expected)
    }

    @Test func blob_returnsStoredBytes() async throws {
        let store = try SwiftDataStore.inMemory()
        let reader = EvidenceReader(store: store, aggregator: Self.aggregator)
        let blob = Data("%PDF-1.7".utf8)
        let item = Self.evidence(on: Self.date(2026, 3, 4), note: "with blob")
        try await store.perform { try await store.write(evidence: item, blob: blob) }

        #expect(try await reader.blob(for: item.id) == blob)
    }
}
