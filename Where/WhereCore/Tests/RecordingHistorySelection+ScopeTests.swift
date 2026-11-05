import Foundation
import Testing
@testable import WhereCore

struct RecordingHistorySelectionScopeTests {
    @Test func clippingRetainsProvenanceAndCannotExpandAssessedCoverage() throws {
        let first = try RecordingAssessmentTestSupport.track(moving: true)
        let other = try RecordingAssessmentTestSupport.track(
            deviceID: RecordingAssessmentTestSupport.second,
            longitude: -74,
            moving: true,
            region: .newYork,
        )
        let selection = try RecordingHistorySelectionTestSupport.resolve(first + other)
        let period = try RecordingAssessmentTestSupport.period(300, 400)
        let clipped = try selection.clipped(to: period)
        #expect(clipped.policyVersion == selection.policyVersion)
        #expect(clipped.controls.map(\.period) == [period])
        #expect(clipped.segments.map(\.period) == [period])
        #expect(clipped.issues.first?.period == period)
        #expect(clipped.issues.first?.days == selection.issues.first?.days)
        #expect(clipped.issues.first?.sampleIDs == selection.issues.first?.sampleIDs)
        #expect(try clipped.clipped(to: RecordingAssessmentTestSupport.period(0, 1201)) == clipped)
    }
}
