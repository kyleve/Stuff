import Foundation
import RegionKit
import Testing
import WhereCore
@testable import WhereUI

struct WhereFormatRecordingReviewTests {
    @Test(arguments: [false, true])
    func contributionsDistinguishUnknownGeographyFromReportingGroups(includesKnown: Bool) {
        let day = DayPresence(
            day: CalendarDay(year: 2026, month: 7, day: 15),
            regions: includesKnown ? [.california, .other] : [.other],
        )
        let label = WhereFormat.recordingRegions(day)
        #expect(label.contains(String(localized: .recordingReviewUnknownRegion)))
        #expect(!label.contains(Region.other.localizedName))
        if includesKnown { #expect(label.contains(Region.california.localizedName)) }
    }

    @Test func unknownDatesRemainDistinctFromNoRecordedDatesAndKeepKnownCandidates() {
        let day = CalendarDay(year: 2026, month: 7, day: 15)
        let known = WhereFormat.recordingDays(.known([day]))
        let unknown = WhereFormat.recordingDays(.unassigned(known: [day]))
        #expect(unknown.contains(known))
        #expect(unknown.contains(String(localized: .recordingReviewUnknownDate)))
        #expect(WhereFormat.recordingDays(.unassigned(known: [])) != WhereFormat
            .recordingDays(.known([])))
    }

    @Test func unknownGeographyDoesNotBecomeExcludedOrAReportingRegion() throws {
        let sample = try RecordingReviewTestSupport.sample(
            deviceID: RecordingReviewTestSupport.first,
            seconds: 0,
        )
        let unknown = try RecordingObservation(
            sample: sample,
            recordingDay: .unresolved,
            region: nil,
        )
        let excluded = try RecordingObservation(
            sample: sample,
            recordingDay: .unresolved,
            geography: .init(knownRegions: [], includesUnknownPresence: false),
        )
        #expect(WhereFormat.recordingObservation(unknown)
            .contains(String(localized: .recordingReviewUnknownRegion)))
        #expect(WhereFormat.recordingObservation(excluded)
            .contains(String(localized: .recordingReviewExcluded)))
        #expect(WhereFormat.recordingObservation(unknown) != WhereFormat
            .recordingObservation(excluded))
    }
}
