import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct LocationHistoryReaderInventoryTests {
    @Test func recordedLogicalYearSurvivesAChangedViewingZone() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let zone = try #require(TimeZone(secondsFromGMT: -3600))
        let sample = try LocationHistoryReaderTestSupport.sample(seconds: 0, zone: zone)
        try await LocationHistoryReaderTestSupport.add([sample], to: store)
        var viewing = Calendar(identifier: .gregorian)
        viewing.timeZone = try #require(TimeZone(secondsFromGMT: 14 * 3600))
        #expect(try await LocationHistoryReaderTestSupport.reader(store)
            .historyYears(calendar: viewing) == [2000])
    }

    @Test func calendarRecoveryReplacesPossibleSearchYearsWithTheEstablishedYear() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let sample = try LocationHistoryReaderTestSupport.sample(
            seconds: 10,
            assignment: .unresolved,
        )
        try await LocationHistoryReaderTestSupport.add([sample], to: store)
        let reader = LocationHistoryReaderTestSupport.reader(store)
        let calendar = LocationHistoryReaderTestSupport.calendar
        #expect(try await reader.historyYears(calendar: calendar) == [2000, 2001])
        try await RecordingChoiceTestSupport.append(.calendar(RecordingControlsTestSupport.calendar(
            1801,
            action: .establish(.init(timeZone: .gmt, secondsFromGMT: 0)),
        )), store: store)
        #expect(try await reader.historyYears(calendar: calendar) == [2001])
        #expect(try await store.allSamples() == [sample])
    }

    @Test func removedObservationsDoNotInventAnOtherwiseAbsentHistoryYear() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let samples = try [0.0, 365 * 86400]
            .map { try LocationHistoryReaderTestSupport.sample(seconds: $0) }
        try await LocationHistoryReaderTestSupport.add(samples, to: store)
        try await store.perform {
            try await store.addRecordingDeviceRemoval(.init(
                id: .init(rawValue: UUID()),
                deviceID: RecordingAssessmentTestSupport.first,
                removedAt: RecordingAssessmentTestSupport.time(100),
                removedByDeviceID: RecordingAssessmentTestSupport.second,
            ))
        }
        #expect(try await LocationHistoryReaderTestSupport.reader(store).historyYears(
            calendar: LocationHistoryReaderTestSupport.calendar,
        ) == [2001])
    }

    @Test func wholeDayChoiceRetainsItsYearAndMissingPredecessorsAddPossibleYears() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let day = CalendarDay(year: 2000, month: 12, day: 31)
        let period = try RecordingAssessmentTestSupport.period(-23 * 3600, 3600)
        let original = try HistoryDecision(
            id: .init(rawValue: UUID()),
            author: RecordingAssessmentTestSupport.first,
            periods: [period],
            scope: .recordingDay(
                deviceID: RecordingAssessmentTestSupport.first,
                day: day,
            ),
            action: .select(RecordingAssessmentTestSupport.first),
            predecessors: [],
            version: RecordingEvidencePolicy.version,
        )
        try await RecordingChoiceTestSupport.append(.source(original), store: store)
        let reader = LocationHistoryReaderTestSupport.reader(store)
        let calendar = LocationHistoryReaderTestSupport.calendar
        #expect(try await reader.historyYears(calendar: calendar) == [2000])
        let incomplete = try HistoryDecision(
            id: .init(rawValue: UUID()),
            author: RecordingAssessmentTestSupport.first,
            periods: [period],
            scope: original.scope,
            action: original.action,
            predecessors: [.init(rawValue: UUID())],
            version: RecordingEvidencePolicy.version,
        )
        try await RecordingChoiceTestSupport.append(.source(incomplete), store: store)
        #expect(try await reader.historyYears(calendar: calendar) == [2000, 2001])
    }

    @Test func emptySourceChoicesAndOpaquePeriodsStillRequireHistoricalDiscovery() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        let sourcePeriod = try RecordingPeriod(
            start: WhereCoreTestSupport.iso("1998-07-01T12:00:00Z"),
            end: WhereCoreTestSupport.iso("1998-07-01T13:00:00Z"),
        )
        let source = try HistoryDecision(
            id: .init(rawValue: UUID()),
            author: RecordingAssessmentTestSupport.first,
            periods: [sourcePeriod],
            scope: .fixedPeriods,
            action: .select(RecordingAssessmentTestSupport.first),
            predecessors: [],
            version: RecordingEvidencePolicy.version,
        )
        try await RecordingChoiceTestSupport.append(.source(source), store: store)
        let opaque = try VersionedHistoryRecord(
            id: .init(rawValue: UUID()),
            dataGenerationID: .initial,
            semantics: .init(major: 1, minor: 1, patch: 0),
            scope: .periods([RecordingAssessmentTestSupport.period(0, 100)]),
            kind: "fixture.future-control",
            payload: Data(),
        )
        try await store.perform { try await store.addVersionedHistoryRecord(opaque) }
        #expect(try await LocationHistoryReaderTestSupport.reader(store).historyYears(
            calendar: LocationHistoryReaderTestSupport.calendar,
        ) == [1998, 2000, 2001])
    }

    @Test func ordinaryHintsAloneDoNotCreateHistoryYears() async throws {
        let store = try await RecordingChoiceTestSupport.store()
        try await RecordingChoiceTestSupport.append(
            .ignore(RecordingControlsTestSupport.ignore(1811)),
            store: store,
        )
        try await RecordingChoiceTestSupport.append(
            .place(RecordingControlsTestSupport.place(1812)),
            store: store,
        )
        try await RecordingChoiceTestSupport.append(.calendar(RecordingControlsTestSupport.calendar(
            1813,
            action: .establish(.init(timeZone: .gmt, secondsFromGMT: 0)),
        )), store: store)
        #expect(try await LocationHistoryReaderTestSupport.reader(store).historyYears(
            calendar: LocationHistoryReaderTestSupport.calendar,
        ).isEmpty)
    }
}
