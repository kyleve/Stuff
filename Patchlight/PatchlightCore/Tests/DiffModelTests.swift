import PatchlightCore
import Testing

struct DiffModelTests {
    @Test func reviewDepthIsMonotonicAndBalancedIsTheMiddle() {
        #expect(ReviewDepth.allCases == [
            .critical,
            .focused,
            .balanced,
            .thorough,
            .everything,
        ])
        #expect(ReviewDepth.focused < .balanced)
        #expect(ReviewDepth.balanced < .thorough)
    }

    @Test func assessmentClampsUntrustedConfidence() {
        let hunkID = DiffHunk.ID(rawValue: "hunk")
        #expect(ReviewAssessment(
            hunkID: hunkID,
            category: .risk,
            minimumDepth: .critical,
            confidence: 4,
            evidence: [],
            isPartial: false,
        ).confidence == 1)
        #expect(ReviewAssessment(
            hunkID: hunkID,
            category: .unknown,
            minimumDepth: .balanced,
            confidence: -1,
            evidence: [],
            isPartial: true,
        ).confidence == 0)
    }
}
