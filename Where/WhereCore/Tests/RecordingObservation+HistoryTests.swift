import Foundation
import Testing
@testable import WhereCore

struct RecordingObservationHistoryTests {
    @Test func correctionsAndTheirResetUseTheSameSpecificGeographyAsHistory() throws {
        let sample = try LocationHistoryReaderTestSupport.sample(seconds: 0)
        let first = SampleAttributionRevision(
            id: .init(rawValue: UUID()),
            sampleID: sample.id,
            updatedAt: RecordingAssessmentTestSupport.time(1),
            replacementRegions: [.newYork],
        )
        let reset = SampleAttributionRevision(
            id: .init(rawValue: UUID()),
            sampleID: sample.id,
            updatedAt: RecordingAssessmentTestSupport.time(2),
            replacementRegions: nil,
        )
        let controls = try RecordingControlSelectionTestSupport.snapshot([])
        let corrected = try RecordingObservation.history(
            samples: [sample],
            corrections: [first],
            controls: controls,
            catalog: LocationHistoryReaderTestSupport.Geography(),
            version: RecordingEvidencePolicy.version,
        )
        #expect(corrected.first?.geography.knownRegions == [.newYork])
        let restored = try RecordingObservation.history(
            samples: [sample],
            corrections: [reset, first],
            controls: controls,
            catalog: LocationHistoryReaderTestSupport.Geography(),
            version: RecordingEvidencePolicy.version,
        )
        #expect(restored.first?.geography.knownRegions == [.california])
        #expect(restored.first?.sample == sample)
    }

    @Test func calendarRecoveryResolvesRawUnknownWithoutReplacingTheRawAssignment() throws {
        let sample = try LocationHistoryReaderTestSupport.sample(
            seconds: 0,
            assignment: .unresolved,
        )
        let context = try RecordingControlsTestSupport.calendar(
            1901,
            action: .establish(.init(timeZone: .gmt, secondsFromGMT: 0)),
        )
        let result = try RecordingObservation.history(
            samples: [sample],
            corrections: [],
            controls: RecordingControlSelectionTestSupport.snapshot([.calendar(context)]),
            catalog: LocationHistoryReaderTestSupport.Geography(),
            version: RecordingEvidencePolicy.version,
        )
        #expect(result.first?.recordingDay.day == CalendarDay(year: 2001, month: 1, day: 1))
        #expect(result.first?.sample.recordingDay == .unresolved)
    }
}
