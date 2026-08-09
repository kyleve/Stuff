import Foundation
import PatchlightCore

enum ProviderAnalysisTestSupport {
    static func request() -> ReviewAnalysisRequest {
        let hunk = DiffHunk(
            id: DiffHunk.ID(rawValue: "hunk-1"),
            header: "@@ -1 +1 @@",
            oldStart: 1,
            oldCount: 1,
            newStart: 1,
            newCount: 1,
            lines: [
                DiffLine(
                    id: DiffLine.ID(rawValue: "old"),
                    kind: .deletion,
                    oldLine: 1,
                    newLine: nil,
                    text: "let enabled = false",
                ),
                DiffLine(
                    id: DiffLine.ID(rawValue: "new"),
                    kind: .addition,
                    oldLine: nil,
                    newLine: 1,
                    text: "let enabled = true",
                ),
            ],
        )
        return ReviewAnalysisRequest(
            pullRequest: PatchlightCoreTestSupport.pullRequestID,
            baseOID: PatchlightCoreTestSupport.objectID("a"),
            headOID: PatchlightCoreTestSupport.objectID("b"),
            files: [DiffFile(
                path: "Sources/App.swift",
                previousPath: nil,
                status: .modified,
                additions: 1,
                deletions: 1,
                baseBlobOID: PatchlightCoreTestSupport.objectID("c"),
                headBlobOID: PatchlightCoreTestSupport.objectID("d"),
                availability: .complete,
                hunks: [hunk],
            )],
        )
    }

    static func selection(provider: AIProvider) throws -> AnalysisModelSelection {
        try AnalysisModelSelection(
            provider: provider,
            preset: .balanced,
            advancedModelID: nil,
        )
    }

    static func budget(provider: AIProvider) throws -> AnalysisRunBudgetController {
        try AnalysisRunBudgetController(limits: selection(provider: provider).budget)
    }

    static func github() -> ProviderToolGitHub {
        let request = request()
        return ProviderToolGitHub(
            headOID: request.headOID,
            blobOID: PatchlightCoreTestSupport.objectID("d"),
            blob: Data("let enabled = true".utf8),
        )
    }

    static func tools(
        github: ProviderToolGitHub,
        budget: AnalysisRunBudgetController,
    ) -> AnalysisRepositoryTools {
        let request = request()
        return AnalysisRepositoryTools(
            github: github,
            repository: request.pullRequest.repository,
            baseOID: request.baseOID,
            headOID: request.headOID,
            budget: budget,
        )
    }

    static func structuredReview(hunkID: String = "hunk-1") -> String {
        """
        {"summary":"Review the behavior toggle.","hunks":[{"hunk_id":"\(
            hunkID
        )","category":"behavior","minimum_depth":"focused","confidence":0.96,"risk_signals":["Behavior changes"],"test_signals":["No changed test"],"evidence":["The boolean flips"],"findings":[{"title":"Verify intent","body":"Confirm this default should change.","side":"head","line":1}]}],"files":[{"path":"Sources/App.swift","summary":"Changes the default.","minimum_depth":"focused"}]}
        """
    }

    static func json(_ object: Any) -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        } catch {
            preconditionFailure("Provider test JSON must be valid: \(error)")
        }
    }

    static func response(_ object: Any) -> PatchlightHTTPResponse {
        PatchlightHTTPResponse(statusCode: 200, headers: [:], body: json(object))
    }
}

actor ProviderToolGitHub: GitHubReading {
    let headOID: GitObjectID
    let blobOID: GitObjectID
    let blobData: Data

    init(headOID: GitObjectID, blobOID: GitObjectID, blob: Data) {
        self.headOID = headOID
        self.blobOID = blobOID
        blobData = blob
    }

    func tree(repository _: RepositoryID, oid: GitObjectID) throws -> RepositoryTree {
        guard oid == headOID else { return RepositoryTree(entries: [], isComplete: true) }
        return RepositoryTree(
            entries: [RepositoryTreeEntry(
                path: "Sources/App.swift",
                kind: .blob,
                oid: blobOID,
                byteCount: blobData.count,
            )],
            isComplete: true,
        )
    }

    func blob(repository _: RepositoryID, oid: GitObjectID, path _: String) throws -> Data {
        guard oid == blobOID else { throw Failure.missing }
        return blobData
    }

    func viewer() throws -> GitHubViewer {
        throw Failure.unused
    }

    func dashboard() throws -> ReviewDashboard {
        throw Failure.unused
    }

    func installations() throws -> [GitHubInstallationSummary] {
        throw Failure.unused
    }

    func repositories() throws -> [RepositorySummary] {
        throw Failure.unused
    }

    func reviewRequests() throws -> [PullRequestSummary] {
        throw Failure.unused
    }

    func ownPullRequests() throws -> [PullRequestSummary] {
        throw Failure.unused
    }

    func pullRequests(in _: RepositoryID) throws -> [PullRequestSummary] {
        throw Failure.unused
    }

    func workspace(for _: PullRequestID) throws -> PullRequestWorkspace {
        throw Failure.unused
    }

    private enum Failure: Error {
        case missing
        case unused
    }
}
