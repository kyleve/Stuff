import Foundation
import PatchlightCore
import Testing

struct AnalysisRepositoryToolsTests {
    @Test func toolsStayPinnedToExactTreesAndReportRetrievedContext() async throws {
        let baseOID = PatchlightCoreTestSupport.objectID("a")
        let headOID = PatchlightCoreTestSupport.objectID("b")
        let sourceOID = PatchlightCoreTestSupport.objectID("c")
        let github = ToolGitHub(
            trees: [
                baseOID: RepositoryTree(
                    entries: [
                        RepositoryTreeEntry(
                            path: "Sources/App.swift",
                            kind: .blob,
                            oid: sourceOID,
                            byteCount: 12,
                        ),
                        RepositoryTreeEntry(
                            path: "Tests/AppTests.swift",
                            kind: .blob,
                            oid: PatchlightCoreTestSupport.objectID("d"),
                            byteCount: 10,
                        ),
                    ],
                    isComplete: true,
                ),
                headOID: RepositoryTree(entries: [], isComplete: false),
            ],
            blobs: [sourceOID: Data("let value = 1".utf8)],
        )
        let budget = AnalysisRunBudgetController(limits: budget(extraContextBytes: 4096))
        let tools = AnalysisRepositoryTools(
            github: github,
            repository: PatchlightCoreTestSupport.repositoryID,
            baseOID: baseOID,
            headOID: headOID,
            budget: budget,
        )

        let listed = try await tools.execute(AnalysisToolCall(
            name: .listPaths,
            revision: .base,
            path: nil,
            query: nil,
            prefix: "Sources/",
            limit: 20,
        ))
        let read = try await tools.execute(AnalysisToolCall(
            name: .readFile,
            revision: .base,
            path: "Sources/App.swift",
            query: nil,
            prefix: nil,
            limit: nil,
        ))

        #expect(listed.paths == ["Sources/App.swift"])
        #expect(read.text == "let value = 1")
        #expect(await github.requestedTreeOIDs == [baseOID])
        #expect(await github.requestedBlobOIDs == [sourceOID])
        let metrics = await budget.toolMetrics()
        #expect(metrics.toolCalls == 2)
        #expect(metrics.filesRetrieved == 1)
        #expect(metrics.bytesRetrieved > 0)
    }

    @Test func toolsRejectTraversalOversizedFilesAndContextOverflow() async throws {
        let baseOID = PatchlightCoreTestSupport.objectID("a")
        let largeOID = PatchlightCoreTestSupport.objectID("c")
        let github = ToolGitHub(
            trees: [baseOID: RepositoryTree(
                entries: [RepositoryTreeEntry(
                    path: "Large.txt",
                    kind: .blob,
                    oid: largeOID,
                    byteCount: AnalysisRepositoryTools.maximumFileBytes + 1,
                )],
                isComplete: true,
            )],
            blobs: [:],
        )
        let controller = AnalysisRunBudgetController(limits: budget(extraContextBytes: 1))
        let tools = AnalysisRepositoryTools(
            github: github,
            repository: PatchlightCoreTestSupport.repositoryID,
            baseOID: baseOID,
            headOID: PatchlightCoreTestSupport.objectID("b"),
            budget: controller,
        )

        await #expect(throws: AIAnalysisError.invalidToolRequest) {
            try await tools.execute(AnalysisToolCall(
                name: .readFile,
                revision: .base,
                path: "../Secrets.txt",
                query: nil,
                prefix: nil,
                limit: nil,
            ))
        }
        await #expect(throws: AIAnalysisError.fileTooLarge) {
            try await tools.execute(AnalysisToolCall(
                name: .readFile,
                revision: .base,
                path: "Large.txt",
                query: nil,
                prefix: nil,
                limit: nil,
            ))
        }
        await #expect(throws: AIAnalysisError.contextBudgetExceeded) {
            try await tools.execute(AnalysisToolCall(
                name: .listPaths,
                revision: .base,
                path: nil,
                query: nil,
                prefix: nil,
                limit: 10,
            ))
        }
    }

    private func budget(extraContextBytes: Int) -> AnalysisBudget {
        AnalysisBudget(
            diffBytes: 1024,
            extraContextBytes: extraContextBytes,
            maximumProviderCalls: 2,
            maximumTurns: 2,
        )
    }
}

private actor ToolGitHub: GitHubReading {
    let trees: [GitObjectID: RepositoryTree]
    let blobs: [GitObjectID: Data]
    private(set) var requestedTreeOIDs: [GitObjectID] = []
    private(set) var requestedBlobOIDs: [GitObjectID] = []

    init(trees: [GitObjectID: RepositoryTree], blobs: [GitObjectID: Data]) {
        self.trees = trees
        self.blobs = blobs
    }

    func tree(repository _: RepositoryID, oid: GitObjectID) throws -> RepositoryTree {
        requestedTreeOIDs.append(oid)
        guard let value = trees[oid] else { throw ToolFailure.missing }
        return value
    }

    func blob(repository _: RepositoryID, oid: GitObjectID, path _: String) throws -> Data {
        requestedBlobOIDs.append(oid)
        guard let value = blobs[oid] else { throw ToolFailure.missing }
        return value
    }

    func viewer() throws -> GitHubViewer {
        throw ToolFailure.unused
    }

    func dashboard() throws -> ReviewDashboard {
        throw ToolFailure.unused
    }

    func installations() throws -> [GitHubInstallationSummary] {
        throw ToolFailure.unused
    }

    func repositories() throws -> [RepositorySummary] {
        throw ToolFailure.unused
    }

    func reviewRequests() throws -> [PullRequestSummary] {
        throw ToolFailure.unused
    }

    func ownPullRequests() throws -> [PullRequestSummary] {
        throw ToolFailure.unused
    }

    func pullRequests(in _: RepositoryID) throws -> [PullRequestSummary] {
        throw ToolFailure.unused
    }

    func workspace(for _: PullRequestID) throws -> PullRequestWorkspace {
        throw ToolFailure.unused
    }

    private enum ToolFailure: Error {
        case missing
        case unused
    }
}
