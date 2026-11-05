import Foundation
@testable import WhereCore

enum RecordingHistorySelectionTestSupport {
    static func midnightObservations() throws -> [RecordingObservation] {
        guard let previousDayZone = TimeZone(secondsFromGMT: -3600) else {
            preconditionFailure("The fixed test offset must be supported.")
        }
        return try [-600.0, 0].flatMap { timestamp in
            try [
                RecordingAssessmentTestSupport.observation(seconds: timestamp),
                RecordingAssessmentTestSupport.observation(
                    deviceID: RecordingAssessmentTestSupport.second,
                    seconds: timestamp,
                    timeZone: previousDayZone,
                ),
            ]
        }
    }

    static func years(
        _ observations: [RecordingObservation],
        from first: Int,
        through last: Int,
    ) throws -> RecordingHistorySelection {
        let period = try LocationHistoryQuery.days(
            CalendarDay(year: first, month: 1, day: 1) ... CalendarDay(
                year: last,
                month: 12,
                day: 31,
            ),
        ).recordingPeriod()
        return try resolve(
            observations,
            start: period.start.timeIntervalSinceReferenceDate,
            end: period.end.timeIntervalSinceReferenceDate,
        )
    }

    static func resolve(
        _ observations: [RecordingObservation],
        controls: [RecordingControl] = [],
        removals: [RecordingDeviceRemoval] = [],
        start: Double = 0,
        end: Double = 1201,
    ) throws -> RecordingHistorySelection {
        try RecordingHistorySelection.resolve(
            observations: observations,
            controls: RecordingControlSelectionTestSupport.snapshot(controls),
            removals: removals,
            within: RecordingAssessmentTestSupport.period(start, end),
            version: RecordingEvidencePolicy.version,
        )
    }
}
