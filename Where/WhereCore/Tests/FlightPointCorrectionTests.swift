import Foundation
import Testing
@testable import WhereCore

struct FlightPointCorrectionTests {
    @Test func recordingPreviewRetainsLogicalDayAndManualSupport() throws {
        let observations = try RecordingAssessmentTestSupport.track(moving: true)
        let point = try #require(observations.first)
        let day = try #require(point.recordingDay.day)
        let selected = try RecordingHistorySelectionTestSupport.resolve(observations)
            .replacingGeography([point.sample.id: []])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: -12 * 3600))
        let correction = try FlightPointCorrection(
            sampleID: point.sample.id,
            action: .restoreGPS,
            day: day,
            dataGenerationID: .initial,
            evidence: .init(
                history: .init(
                    samples: selected.attributedSamples(),
                    revisions: [],
                    contract: .recording(selected),
                ),
                manualDays: [DayPresence(day: day, regions: [.canada])],
                primaryRegions: [.california, .newYork],
                trackedRegions: [.california, .newYork],
                driftThresholdMeters: 1000,
                calendar: calendar,
                flights: [],
            ),
            regionPreview: .recording(replacement: [.newYork]),
        )
        #expect(CalendarDay(from: point.sample.timestamp, in: calendar) != day)
        #expect(try correction.resultingRegions == [.california, .newYork, .canada])
        #expect(selected.contributions.first?.geography.presence == [])
    }
}
