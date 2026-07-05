@_spi(Testing) import ForemanCore
import Foundation
import Testing

@MainActor
struct RepoDiscoveryTests {
    private let fileManager = FileManager.default

    /// Creates a subdirectory of `base`, optionally containing a `.git` entry.
    private func addDirectory(
        _ name: String,
        in base: URL,
        git: GitEntry?,
    ) throws {
        let directory = base.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        switch git {
            case .directory:
                try fileManager.createDirectory(
                    at: directory.appendingPathComponent(".git", isDirectory: true),
                    withIntermediateDirectories: true,
                )
            case .file:
                // Worktrees and submodules use a `.git` *file* pointing at the
                // real git dir.
                try Data("gitdir: /elsewhere/.git\n".utf8)
                    .write(to: directory.appendingPathComponent(".git"))
            case nil:
                break
        }
    }

    private enum GitEntry {
        case directory
        case file
    }

    // MARK: - Directory listing

    @Test func findsOnlyDirectoriesContainingGitEntries() throws {
        let base = try makeTemporaryDirectory()
        try addDirectory("Clone", in: base, git: .directory)
        try addDirectory("Worktree", in: base, git: .file)
        try addDirectory("NotARepo", in: base, git: nil)
        try Data("just a file".utf8).write(to: base.appendingPathComponent("stray.txt"))

        let repos = try RepoDiscovery.scan(base)

        #expect(repos.map(\.name) == ["Clone", "Worktree"])
        #expect(repos.map(\.rootURL.lastPathComponent) == ["Clone", "Worktree"])
    }

    @Test func skipsHiddenDirectories() throws {
        let base = try makeTemporaryDirectory()
        try addDirectory(".hidden", in: base, git: .directory)
        try addDirectory("Visible", in: base, git: .directory)

        let repos = try RepoDiscovery.scan(base)

        #expect(repos.map(\.name) == ["Visible"])
    }

    @Test func sortsCaseInsensitivelyByName() throws {
        let base = try makeTemporaryDirectory()
        try addDirectory("beta", in: base, git: .directory)
        try addDirectory("Alpha", in: base, git: .directory)
        try addDirectory("gamma", in: base, git: .directory)

        let repos = try RepoDiscovery.scan(base)

        #expect(repos.map(\.name) == ["Alpha", "beta", "gamma"])
    }

    @Test func missingScanDirectoryThrows() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForemanCoreTests-missing-\(UUID().uuidString)")

        #expect(throws: (any Error).self) {
            try RepoDiscovery.scan(missing)
        }
    }

    @Test func repoIDIsTheAbsolutePathWithoutATrailingSlash() {
        let scanned = ScannedRepo(
            name: "Thing",
            rootURL: URL(fileURLWithPath: "/Users/dev/Development/Thing/", isDirectory: true),
        )

        #expect(scanned.id == RepoID(rawValue: "/Users/dev/Development/Thing"))
    }

    // MARK: - Stateful rescans

    private struct Fixture {
        let discovery: RepoDiscovery
        let base: URL
        let scanDirectory: URL
    }

    private func makeFixture() throws -> Fixture {
        let base = try makeTemporaryDirectory()
        let scanDirectory = base.appendingPathComponent("Development", isDirectory: true)
        try fileManager.createDirectory(at: scanDirectory, withIntermediateDirectories: true)
        let executable = try makeStubExecutable(
            in: base,
            script: "#!/bin/sh\nwhile true; do sleep 0.1; done\n",
        )
        let logDirectory = base.appendingPathComponent("logs")
        let discovery = RepoDiscovery { scanned in
            makeStubRepo(scanned: scanned, logDirectory: logDirectory, executable: executable)
        }
        return Fixture(discovery: discovery, base: base, scanDirectory: scanDirectory)
    }

    @Test func rescanBuildsSortedRepos() throws {
        let fixture = try makeFixture()
        try addDirectory("beta", in: fixture.scanDirectory, git: .directory)
        try addDirectory("Alpha", in: fixture.scanDirectory, git: .directory)

        try fixture.discovery.rescan(in: fixture.scanDirectory)

        #expect(fixture.discovery.repos.map(\.name) == ["Alpha", "beta"])
    }

    @Test func rescanReusesExistingInstancesById() throws {
        let fixture = try makeFixture()
        try addDirectory("Thing", in: fixture.scanDirectory, git: .directory)
        try fixture.discovery.rescan(in: fixture.scanDirectory)
        let original = try #require(fixture.discovery.repos.first)

        try addDirectory("Other", in: fixture.scanDirectory, git: .directory)
        try fixture.discovery.rescan(in: fixture.scanDirectory)

        #expect(fixture.discovery.repos.count == 2)
        let reused = try #require(fixture.discovery.repos.first { $0.name == "Thing" })
        #expect(reused === original)
    }

    @Test func rescanStopsAndDropsVanishedReposWorkers() async throws {
        let fixture = try makeFixture()
        try addDirectory("Doomed", in: fixture.scanDirectory, git: .directory)
        try fixture.discovery.rescan(in: fixture.scanDirectory)
        let doomed = try #require(fixture.discovery.repos.first)

        doomed.isEnabled = true
        try await waitUntil("worker reaches running") {
            doomed.worker.state.isLive
        }

        try fileManager.removeItem(at: doomed.rootURL)
        try fixture.discovery.rescan(in: fixture.scanDirectory)

        #expect(fixture.discovery.repos.isEmpty)
        // The dropped repo's worker was told to stop and settles cleanly.
        try await waitUntil("vanished repo's worker stops") {
            doomed.worker.state == .stopped
        }
    }

    @Test func failedRescanKeepsExistingRepos() throws {
        let fixture = try makeFixture()
        try addDirectory("Thing", in: fixture.scanDirectory, git: .directory)
        try fixture.discovery.rescan(in: fixture.scanDirectory)

        let missing = fixture.base.appendingPathComponent("nope")
        #expect(throws: (any Error).self) {
            try fixture.discovery.rescan(in: missing)
        }

        #expect(fixture.discovery.repos.map(\.name) == ["Thing"])
    }
}
