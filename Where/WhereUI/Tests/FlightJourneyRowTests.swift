import Foundation
import Testing
@testable import WhereUI

@MainActor
struct FlightJourneyRowTests {
    @Test(arguments: [-12, 0, 14])
    func recordingLabelsPreserveThePriorYearAndSkippedDate(viewingOffset: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: viewingOffset * 3600))
        let priorYear = try FlightJourneyRow(
            flight: RecordingFlightPreview.flight(.priorYear),
            calendar: calendar,
            isFirst: true,
            isLast: true,
        )
        let dateLine = try FlightJourneyRow(
            flight: RecordingFlightPreview.flight(.dateLine),
            calendar: calendar,
            isFirst: true,
            isLast: true,
        )
        #expect(priorYear.dateLabels == ["Dec 31"])
        #expect(dateLine.dateLabels == ["Dec 31", "Jan 2"])
    }
}
