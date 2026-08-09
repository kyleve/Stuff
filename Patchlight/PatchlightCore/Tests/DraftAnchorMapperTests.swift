import Foundation
import PatchlightCore
import Testing

struct DraftAnchorMapperTests {
    @Test func uniqueRenameAndContextRemapsWithoutSubmitting() throws {
        let oldHead = PatchlightCoreTestSupport.objectID("a")
        let newHead = PatchlightCoreTestSupport.objectID("b")
        let lines = [
            DiffLine(
                id: .init(rawValue: "1"),
                kind: .context,
                oldLine: 4,
                newLine: 4,
                text: "before",
            ),
            DiffLine(
                id: .init(rawValue: "2"),
                kind: .addition,
                oldLine: nil,
                newLine: 5,
                text: "changed",
            ),
            DiffLine(
                id: .init(rawValue: "3"),
                kind: .context,
                oldLine: 5,
                newLine: 6,
                text: "after",
            ),
        ]
        let fingerprint = DraftAnchorMapper.fingerprint(lineIndex: 1, in: lines)
        let draft = ReviewDraft(
            id: UUID(),
            pullRequest: PatchlightCoreTestSupport.pullRequestID,
            anchor: DiffAnchor(
                path: "Old.swift",
                side: .head,
                commitOID: oldHead,
                blobOID: nil,
                line: 5,
                startLine: nil,
                contextFingerprint: fingerprint,
            ),
            body: "Question",
            updatedAt: Date(),
        )
        let workspace = workspace(head: newHead, files: [DiffFile(
            path: "New.swift",
            previousPath: "Old.swift",
            status: .renamed,
            additions: 1,
            deletions: 0,
            baseBlobOID: PatchlightCoreTestSupport.objectID("c"),
            headBlobOID: PatchlightCoreTestSupport.objectID("d"),
            availability: .complete,
            hunks: [DiffHunk(
                id: .init(rawValue: "h"),
                header: "@@",
                oldStart: 4,
                oldCount: 2,
                newStart: 4,
                newCount: 3,
                lines: lines,
            )],
        )])

        let result = try #require(DraftAnchorMapper.map(
            [draft],
            from: oldHead,
            to: workspace,
        ).first)
        guard case let .remapped(remapped) = result.resolution else {
            Issue.record("Expected a unique remap")
            return
        }
        #expect(remapped.anchor?.path == "New.swift")
        #expect(remapped.anchor?.commitOID == newHead)
        #expect(remapped.anchor?.line == 5)
    }

    @Test func duplicateContextRemainsAmbiguous() throws {
        let oldHead = PatchlightCoreTestSupport.objectID("a")
        let line = DiffLine(
            id: .init(rawValue: "1"),
            kind: .addition,
            oldLine: nil,
            newLine: 1,
            text: "same",
        )
        let fingerprint = DraftAnchorMapper.fingerprint(lineIndex: 0, in: [line])
        let draft = ReviewDraft(
            id: UUID(),
            pullRequest: PatchlightCoreTestSupport.pullRequestID,
            anchor: DiffAnchor(
                path: "File.swift",
                side: .head,
                commitOID: oldHead,
                blobOID: nil,
                line: 1,
                startLine: nil,
                contextFingerprint: fingerprint,
            ),
            body: "Question",
            updatedAt: Date(),
        )
        let hunk = DiffHunk(
            id: .init(rawValue: "h"),
            header: "@@",
            oldStart: 1,
            oldCount: 0,
            newStart: 1,
            newCount: 1,
            lines: [line],
        )
        let file = DiffFile(
            path: "File.swift",
            previousPath: nil,
            status: .modified,
            additions: 2,
            deletions: 0,
            baseBlobOID: nil,
            headBlobOID: nil,
            availability: .complete,
            hunks: [hunk, hunk],
        )

        let result = try #require(DraftAnchorMapper.map(
            [draft],
            from: oldHead,
            to: workspace(head: PatchlightCoreTestSupport.objectID("b"), files: [file]),
        ).first)
        #expect(result.resolution == .ambiguous(candidateCount: 2))
    }

    private func workspace(head: GitObjectID, files: [DiffFile]) -> PullRequestWorkspace {
        PullRequestWorkspace(
            summary: PullRequestSummary(
                id: PatchlightCoreTestSupport.pullRequestID,
                repository: RepositoryCoordinates(owner: "acme", name: "widget"),
                title: "Review",
                authorLogin: "author",
                isDraft: false,
                headOID: head,
                updatedAt: Date(),
                reviewRequestSource: .direct,
            ),
            bodyMarkdown: nil,
            baseOID: PatchlightCoreTestSupport.objectID("e"),
            files: files,
            isFileListComplete: true,
        )
    }
}
