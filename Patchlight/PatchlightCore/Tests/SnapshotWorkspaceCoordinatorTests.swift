import Foundation
import PatchlightCore
import Testing
import UIKit

struct SnapshotWorkspaceCoordinatorTests {
    @Test func exactBlobsCacheAndProduceLocalHeatmapMetrics() async throws {
        let setup = try PatchlightCoreTestSupport.makeScope(name: #function)
        let baseOID = PatchlightCoreTestSupport.objectID("a")
        let headOID = PatchlightCoreTestSupport.objectID("b")
        let base = try #require(imageData(patch: nil))
        let head = try #require(imageData(patch: CGRect(x: 1, y: 1, width: 2, height: 2)))
        let github = SnapshotBlobGitHub(blobs: [baseOID: base, headOID: head])
        let coordinator = SnapshotWorkspaceCoordinator(
            github: github,
            readCache: setup.scope.readCache,
            contentCache: setup.scope.cache,
        )
        let file = DiffFile(
            path: "Feature/Tests/Snapshots/Card.png",
            previousPath: nil,
            status: .modified,
            additions: 0,
            deletions: 0,
            baseBlobOID: baseOID,
            headBlobOID: headOID,
            availability: .binary,
            hunks: [],
        )

        let first = try await coordinator.load(
            file: file,
            repository: PatchlightCoreTestSupport.repositoryID,
        )
        _ = try await coordinator.load(
            file: file,
            repository: PatchlightCoreTestSupport.repositoryID,
        )

        guard case let .comparable(metrics, heatmap) = first.comparison else {
            Issue.record("Expected exact local image comparison")
            return
        }
        #expect(metrics.changedPixels == 4)
        #expect(heatmap != nil)
        #expect(await github.blobReadCount == 2)
    }

    private func imageData(patch: CGRect?) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(
            size: CGSize(width: 8, height: 8),
            format: format,
        ).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            if let patch {
                UIColor.white.setFill()
                context.fill(patch)
            }
        }.pngData()
    }
}

private actor SnapshotBlobGitHub: GitHubReading {
    let blobs: [GitObjectID: Data]
    private(set) var blobReadCount = 0

    init(blobs: [GitObjectID: Data]) {
        self.blobs = blobs
    }

    func blob(repository _: RepositoryID, oid: GitObjectID, path _: String) throws -> Data {
        blobReadCount += 1
        guard let value = blobs[oid] else { throw TestFailure.missingBlob }
        return value
    }

    func viewer() throws -> GitHubViewer {
        throw TestFailure.unused
    }

    func dashboard() throws -> ReviewDashboard {
        throw TestFailure.unused
    }

    func installations() throws -> [GitHubInstallationSummary] {
        throw TestFailure.unused
    }

    func repositories() throws -> [RepositorySummary] {
        throw TestFailure.unused
    }

    func reviewRequests() throws -> [PullRequestSummary] {
        throw TestFailure.unused
    }

    func ownPullRequests() throws -> [PullRequestSummary] {
        throw TestFailure.unused
    }

    func pullRequests(in _: RepositoryID) throws -> [PullRequestSummary] {
        throw TestFailure.unused
    }

    func workspace(for _: PullRequestID) throws -> PullRequestWorkspace {
        throw TestFailure.unused
    }

    private enum TestFailure: Error {
        case missingBlob
        case unused
    }
}
