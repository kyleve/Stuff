@_spi(Testing) import ForemanCore
import Foundation
import Testing

/// The handler is a thin request→intent→response map; these confirm the
/// mapping and — crucially — that every failure becomes a `.failure` response
/// (localized reason) rather than a throw escaping to the socket.
@MainActor
struct ControlRequestHandlerTests {
    private func makeHandler(repoNames: [String]) throws
        -> (ControlRequestHandler, ControlServicesFixture)
    {
        let fixture = try makeControlServicesFixture(repoNames: repoNames)
        fixture.services.start()
        return (ControlRequestHandler(services: fixture.services), fixture)
    }

    @Test func describeReportsScanDirectoryAndRepos() async throws {
        let (handler, fixture) = try makeHandler(repoNames: ["Main"])

        guard case let .describe(result) = await handler.handle(.describe) else {
            Issue.record("expected a describe response")
            return
        }
        #expect(result.scanDirectory == fixture.scanDirectory.standardizedFileURL.path)
        #expect(result.repos.map(\.name) == ["Main"])
        #expect(result.repos[0].provenance == nil)
    }

    @Test func adoptReturnsTheRepoStatus() async throws {
        let (handler, fixture) = try makeHandler(repoNames: ["Main"])
        try addGitDirectory("Copy", in: fixture.scanDirectory)
        let copy = fixture.scanDirectory.appendingPathComponent("Copy")

        let response = await handler.handle(.adopt(
            path: copy.path,
            provenance: CopyProvenanceDTO(
                kind: "worktree",
                parentRepoID: fixture.scanDirectory.appendingPathComponent("Main").path,
                branch: "task",
            ),
        ))
        guard case let .repo(status) = response else {
            Issue.record("expected a repo response, got \(response)")
            return
        }
        #expect(status.name == "Copy")
        #expect(status.enabled)
        #expect(status.provenance?.kind == "worktree")
        #expect(status.provenance?.branch == "task")

        fixture.services.stopAll()
    }

    @Test func invalidProvenanceKindBecomesAFailure() async throws {
        let (handler, fixture) = try makeHandler(repoNames: [])
        try addGitDirectory("Copy", in: fixture.scanDirectory)
        let copy = fixture.scanDirectory.appendingPathComponent("Copy")

        let response = await handler.handle(.adopt(
            path: copy.path,
            provenance: CopyProvenanceDTO(kind: "sideways", parentRepoID: "/x", branch: "b"),
        ))
        guard case let .failure(message) = response else {
            Issue.record("expected a failure response, got \(response)")
            return
        }
        #expect(message.contains("sideways"))
    }

    @Test func adoptOutsideScanDirectoryBecomesAFailure() async throws {
        let (handler, fixture) = try makeHandler(repoNames: [])
        // A .git-bearing dir that is NOT under the scan directory.
        let outside = fixture.base.appendingPathComponent("Outside")
        try FileManager.default.createDirectory(
            at: outside.appendingPathComponent(".git"),
            withIntermediateDirectories: true,
        )

        let response = await handler.handle(.adopt(
            path: outside.path,
            provenance: CopyProvenanceDTO(kind: "clone", parentRepoID: "/x", branch: "b"),
        ))
        guard case .failure = response else {
            Issue.record("expected a failure response, got \(response)")
            return
        }
    }

    @Test func removingANonCopyBecomesAFailure() async throws {
        let (handler, fixture) = try makeHandler(repoNames: ["Plain"])
        let plain = fixture.scanDirectory.appendingPathComponent("Plain")

        let response = await handler.handle(.removeCopy(path: plain.path))
        guard case .failure = response else {
            Issue.record("expected a failure response, got \(response)")
            return
        }
        #expect(fixture.remover.worktreeRemovals.isEmpty)
    }
}
