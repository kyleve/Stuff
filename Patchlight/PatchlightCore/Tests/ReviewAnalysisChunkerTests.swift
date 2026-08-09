import PatchlightCore
import Testing

struct ReviewAnalysisChunkerTests {
    @Test func budgetExhaustionKeepsWholeHighRiskHunksBeforeLowerPriorityWork() {
        let critical = file(path: "Sources/Auth.swift", hunkID: "critical", text: "rotate token")
        let mechanical = file(path: "Generated/API.swift", hunkID: "mechanical", text: "generated")
        let workspace = workspace(files: [mechanical, critical])
        let reviewPlan = DeterministicReviewPlan(
            files: [
                filePlan(mechanical, depth: .everything, hard: false),
                filePlan(critical, depth: .critical, hard: true),
            ],
            configurationWarning: nil,
        )
        let criticalBytes = AnalysisDiffRenderer.render(ReviewAnalysisRequest(
            pullRequest: workspace.summary.id,
            baseOID: workspace.baseOID,
            headOID: workspace.summary.headOID,
            files: [critical],
        )).utf8.count

        let result = ReviewAnalysisChunker.plan(
            workspace: workspace,
            reviewPlan: reviewPlan,
            budget: AnalysisBudget(
                diffBytes: criticalBytes,
                extraContextBytes: 0,
                maximumProviderCalls: 1,
                maximumTurns: 1,
            ),
        )

        #expect(result.requests.count == 1)
        #expect(result.requests[0].files.map(\.path) == ["Sources/Auth.swift"])
        #expect(result.requests[0].files[0].hunks.map(\.id.rawValue) == ["critical"])
        #expect(result.omittedHunkIDs == [DiffHunk.ID(rawValue: "mechanical")])
    }

    private func file(path: String, hunkID: String, text: String) -> DiffFile {
        let hunk = DiffHunk(
            id: DiffHunk.ID(rawValue: hunkID),
            header: "@@ -1 +1 @@",
            oldStart: 1,
            oldCount: 1,
            newStart: 1,
            newCount: 1,
            lines: [DiffLine(
                id: DiffLine.ID(rawValue: "\(hunkID)-line"),
                kind: .addition,
                oldLine: nil,
                newLine: 1,
                text: text,
            )],
        )
        return DiffFile(
            path: path,
            previousPath: nil,
            status: .modified,
            additions: 1,
            deletions: 0,
            baseBlobOID: nil,
            headBlobOID: nil,
            availability: .complete,
            hunks: [hunk],
        )
    }

    private func filePlan(
        _ file: DiffFile,
        depth: ReviewDepth,
        hard: Bool,
    ) -> FileReviewPlan {
        let hunks = file.hunks.map { hunk in
            HunkReviewPlan(
                hunk: hunk,
                assessment: ReviewAssessment(
                    hunkID: hunk.id,
                    category: hard ? .risk : .mechanical,
                    minimumDepth: depth,
                    confidence: 1,
                    evidence: [],
                    isPartial: false,
                ),
                isHardSafetySignal: hard,
                hasIndependentMechanicalEvidence: !hard,
                aiAnalysis: nil,
            )
        }
        return FileReviewPlan(
            file: file,
            minimumDepth: depth,
            hunks: hunks,
            isSnapshot: false,
        )
    }

    private func workspace(files: [DiffFile]) -> PullRequestWorkspace {
        PullRequestWorkspace(
            summary: PullRequestSummary(
                id: PatchlightCoreTestSupport.pullRequestID,
                repository: RepositoryCoordinates(owner: "acme", name: "widget"),
                title: "Review",
                authorLogin: "author",
                isDraft: false,
                headOID: PatchlightCoreTestSupport.objectID("h"),
                updatedAt: .distantPast,
                reviewRequestSource: .direct,
            ),
            bodyMarkdown: nil,
            baseOID: PatchlightCoreTestSupport.objectID("b"),
            files: files,
            isFileListComplete: true,
            repositoryConfiguration: .absent,
        )
    }
}
