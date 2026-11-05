import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct RecordingHistorySelectionEvidenceTests {
    @Test func geographicPreviewCannotBypassAnExclusiveSourceOrMutateRawEvidence() throws {
        let first = try RecordingAssessmentTestSupport.track(moving: true)
        let second = try RecordingAssessmentTestSupport.track(
            deviceID: RecordingAssessmentTestSupport.second,
            moving: false,
        )
        let selected = try RecordingHistorySelectionTestSupport.resolve(
            first + second,
            controls: [.source(RecordingAssessmentTestSupport.decision(961, end: 1201))],
        )
        let replacements = Dictionary(uniqueKeysWithValues: first
            .map { ($0.sample.id, Set<Region>()) })
        let preview = try selected.replacingGeography(replacements)
        #expect(preview.contributions.map(\.sample) == first.map(\.sample))
        let allExcluded = preview.contributions.allSatisfy(\.geography.presence.isEmpty)
        #expect(allExcluded)
        #expect(preview.contributions.map(\.recordingDay) == first.map(\.recordingDay))
        #expect(preview.controls == selected.controls)
        #expect(preview.policyVersion == selected.policyVersion)
        #expect(selected.contributions == first)
        #expect(Set(preview.evidence.observations.map(\.sample)) ==
            Set((first + second).map(\.sample)))
    }
}
