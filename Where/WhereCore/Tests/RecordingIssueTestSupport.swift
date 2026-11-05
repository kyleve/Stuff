import Foundation
@testable import WhereCore

enum RecordingIssueTestSupport {
    static let firstDay = CalendarDay(year: 2001, month: 1, day: 1)
    static let secondDay = CalendarDay(year: 2001, month: 1, day: 2)

    static func issue(
        start: Double,
        end: Double,
        days: RecordingHistorySelection.Days = .known([firstDay]),
        problem: RecordingHistorySelection.Problem = .competingTracks([
            RecordingAssessmentTestSupport.first,
            RecordingAssessmentTestSupport.second,
        ]),
        sampleIDs: Set<UUID> = [],
    ) throws -> RecordingHistorySelection.Issue {
        try .init(
            period: RecordingAssessmentTestSupport.period(start, end),
            problem: problem,
            days: days,
            sampleIDs: sampleIDs,
        )
    }
}
