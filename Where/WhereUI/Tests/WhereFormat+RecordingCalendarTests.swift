import Foundation
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct WhereFormatRecordingCalendarTests {
    @Test func theLabelUsesTheSavedOffsetInsteadOfCurrentZoneRules() throws {
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        let summer = try RecordingCalendarContext(timeZone: zone, secondsFromGMT: -14400)
        let winter = try RecordingCalendarContext(timeZone: zone, secondsFromGMT: -18000)
        #expect(WhereFormat.recordingCalendarOffset(summer).contains("-04:00"))
        #expect(WhereFormat.recordingCalendarOffset(winter).contains("-05:00"))
        #expect(WhereFormat.recordingTimeZone(zone) == "America/New York")
        #expect(try WhereFormat.recordingCalendarOffset(.init(timeZone: .gmt, secondsFromGMT: 0))
            .contains("UTC+00:00"))
    }

    @Test func knownRawContextConflictsGiveAnActionableExplanation() {
        let text = WhereFormat.recordingCalendarFailure(
            RecordingCalendarContext.ValidationError.conflictingRecordedContext,
        )
        #expect(text.contains("Narrow the period"))
        #expect(text.contains("already recorded"))
    }
}
