import Foundation
@testable import WhereCore

enum RecordingHistorySelectionTestSupport {
    /// Two agreeing phones, with four fixes each during separated half-hour journeys
    /// distributed across one year. Stable identities make every expected contribution explicit.
    static func annualObservations(count: Int) throws -> [RecordingObservation] {
        precondition(count.isMultiple(of: 8))
        return try (0 ..< count).map { index in
            let journey = index / 8
            let point = (index % 8) / 2
            let seconds = Double(journey) * (365 * 86400 / Double(count / 8))
                + Double(point) * 600
            return try RecordingAssessmentTestSupport.observation(
                deviceID: index.isMultiple(of: 2)
                    ? RecordingAssessmentTestSupport.first : RecordingAssessmentTestSupport.second,
                seconds: seconds,
                sampleID: UUID(uuidString: String(
                    format: "00000000-0000-4000-8000-%012d",
                    500_000 + index,
                ))!,
            )
        }
    }

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
