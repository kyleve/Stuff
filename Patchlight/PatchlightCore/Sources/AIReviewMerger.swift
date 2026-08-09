import Foundation

/// Applies provider classifications without weakening deterministic safety
/// signals or the confidence gates that protect deeper review levels.
public enum AIReviewMerger {
    public static func merge(
        deterministic plan: DeterministicReviewPlan,
        analysis: ReviewAnalysis,
        allowHiding: Bool,
    ) -> DeterministicReviewPlan {
        let byHunk = Dictionary(
            analysis.hunks.map { ($0.assessment.hunkID, $0) },
            uniquingKeysWith: { first, _ in first },
        )
        let files = plan.files.map { filePlan in
            let hunks = filePlan.hunks.map { hunkPlan in
                guard let ai = byHunk[hunkPlan.id] else {
                    return HunkReviewPlan(
                        hunk: hunkPlan.hunk,
                        assessment: ReviewAssessment(
                            hunkID: hunkPlan.id,
                            category: hunkPlan.assessment.category,
                            minimumDepth: hunkPlan.assessment.minimumDepth,
                            confidence: hunkPlan.assessment.confidence,
                            evidence: hunkPlan.assessment.evidence,
                            isPartial: true,
                        ),
                        isHardSafetySignal: hunkPlan.isHardSafetySignal,
                        hasIndependentMechanicalEvidence: hunkPlan
                            .hasIndependentMechanicalEvidence,
                        aiAnalysis: nil,
                    )
                }
                let depth = effectiveDepth(
                    deterministic: hunkPlan,
                    ai: ai,
                    allowHiding: allowHiding,
                )
                return HunkReviewPlan(
                    hunk: hunkPlan.hunk,
                    assessment: ReviewAssessment(
                        hunkID: hunkPlan.id,
                        category: ai.assessment.category,
                        minimumDepth: depth,
                        confidence: ai.assessment.confidence,
                        evidence: hunkPlan.assessment.evidence + ai.assessment.evidence,
                        isPartial: ai.assessment.isPartial,
                    ),
                    isHardSafetySignal: hunkPlan.isHardSafetySignal,
                    hasIndependentMechanicalEvidence: hunkPlan
                        .hasIndependentMechanicalEvidence,
                    aiAnalysis: ai,
                )
            }
            return FileReviewPlan(
                file: filePlan.file,
                minimumDepth: hunks.map(\.assessment.minimumDepth).min()
                    ?? filePlan.minimumDepth,
                hunks: hunks,
                isSnapshot: filePlan.isSnapshot,
            )
        }
        return DeterministicReviewPlan(
            files: files,
            configurationWarning: plan.configurationWarning,
        )
    }

    private static func effectiveDepth(
        deterministic: HunkReviewPlan,
        ai: AIHunkAnalysis,
        allowHiding: Bool,
    ) -> ReviewDepth {
        let proposed = ai.assessment.minimumDepth
        let current = deterministic.assessment.minimumDepth
        guard proposed > current else { return proposed }
        guard allowHiding else { return current }
        guard !deterministic.isHardSafetySignal else { return current }

        if proposed == .everything {
            guard ai.assessment.confidence >= 0.95,
                  deterministic.hasIndependentMechanicalEvidence
            else { return current }
        } else if proposed > .balanced {
            guard ai.assessment.confidence >= 0.90 else { return current }
        } else if proposed > .focused {
            guard ai.assessment.confidence >= 0.80 else { return current }
        }
        return proposed
    }
}
