import Foundation
import PatchlightCore
import Testing

struct AIReviewMergerTests {
    @Test func hardSafetySignalsAlwaysBeatProviderHiding() {
        let deterministic = plan(depth: .critical, hard: true, mechanicalEvidence: true)
        let merged = AIReviewMerger.merge(
            deterministic: deterministic,
            analysis: analysis(depth: .everything, confidence: 1),
            allowHiding: true,
        )
        #expect(merged.files[0].hunks[0].assessment.minimumDepth == .critical)
    }

    @Test func confidenceAndIndependentEvidenceGateDeeperLevels() {
        let cases = [
            GateCase(deterministic: .focused, proposed: .balanced, confidence: 0.79),
            GateCase(deterministic: .balanced, proposed: .thorough, confidence: 0.89),
            GateCase(deterministic: .balanced, proposed: .everything, confidence: 0.99),
        ]
        for value in cases {
            let merged = AIReviewMerger.merge(
                deterministic: plan(
                    depth: value.deterministic,
                    hard: false,
                    mechanicalEvidence: false,
                ),
                analysis: analysis(depth: value.proposed, confidence: value.confidence),
                allowHiding: true,
            )
            #expect(merged.files[0].hunks[0].assessment.minimumDepth == value.deterministic)
        }
    }

    @Test func everythingRequiresConfidenceAndIndependentMechanicalEvidence() {
        let merged = AIReviewMerger.merge(
            deterministic: plan(depth: .balanced, hard: false, mechanicalEvidence: true),
            analysis: analysis(depth: .everything, confidence: 0.95),
            allowHiding: true,
        )
        #expect(merged.files[0].hunks[0].assessment.minimumDepth == .everything)
    }

    @Test func incompleteGitHubFileListsDisableProviderHiding() {
        let merged = AIReviewMerger.merge(
            deterministic: plan(depth: .balanced, hard: false, mechanicalEvidence: true),
            analysis: analysis(depth: .everything, confidence: 1),
            allowHiding: false,
        )
        #expect(merged.files[0].hunks[0].assessment.minimumDepth == .balanced)
    }

    @Test func missingProviderOutputRetainsDeterministicDepthAndBecomesPartial() {
        let deterministic = plan(depth: .focused, hard: false, mechanicalEvidence: false)
        let merged = AIReviewMerger.merge(
            deterministic: deterministic,
            analysis: ReviewAnalysis(hunks: [], files: [], summary: "Partial", usage: .zero),
            allowHiding: true,
        )
        #expect(merged.files[0].hunks[0].assessment.minimumDepth == .focused)
        #expect(merged.files[0].hunks[0].assessment.isPartial)
    }

    private func plan(
        depth: ReviewDepth,
        hard: Bool,
        mechanicalEvidence: Bool,
    ) -> DeterministicReviewPlan {
        let hunk = DiffHunk(
            id: DiffHunk.ID(rawValue: "hunk"),
            header: "@@",
            oldStart: 1,
            oldCount: 1,
            newStart: 1,
            newCount: 1,
            lines: [],
        )
        let hunkPlan = HunkReviewPlan(
            hunk: hunk,
            assessment: ReviewAssessment(
                hunkID: hunk.id,
                category: .unknown,
                minimumDepth: depth,
                confidence: 1,
                evidence: [],
                isPartial: false,
            ),
            isHardSafetySignal: hard,
            hasIndependentMechanicalEvidence: mechanicalEvidence,
            aiAnalysis: nil,
        )
        let file = DiffFile(
            path: "Sources/App.swift",
            previousPath: nil,
            status: .modified,
            additions: 1,
            deletions: 1,
            baseBlobOID: nil,
            headBlobOID: nil,
            availability: .complete,
            hunks: [hunk],
        )
        return DeterministicReviewPlan(
            files: [FileReviewPlan(
                file: file,
                minimumDepth: depth,
                hunks: [hunkPlan],
                isSnapshot: false,
            )],
            configurationWarning: nil,
        )
    }

    private func analysis(depth: ReviewDepth, confidence: Double) -> ReviewAnalysis {
        let assessment = ReviewAssessment(
            hunkID: DiffHunk.ID(rawValue: "hunk"),
            category: .mechanical,
            minimumDepth: depth,
            confidence: confidence,
            evidence: ["Provider evidence"],
            isPartial: false,
        )
        return ReviewAnalysis(
            hunks: [AIHunkAnalysis(
                assessment: assessment,
                riskSignals: [],
                testSignals: [],
                findings: [],
            )],
            files: [],
            summary: "Summary",
            usage: .zero,
        )
    }

    private struct GateCase {
        let deterministic: ReviewDepth
        let proposed: ReviewDepth
        let confidence: Double
    }
}
