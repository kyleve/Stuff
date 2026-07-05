import ForemanCore
import Foundation
import Testing

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

    @Test func findsOnlyDirectoriesContainingGitEntries() throws {
        let base = try makeTemporaryDirectory()
        try addDirectory("Clone", in: base, git: .directory)
        try addDirectory("Worktree", in: base, git: .file)
        try addDirectory("NotARepo", in: base, git: nil)
        try Data("just a file".utf8).write(to: base.appendingPathComponent("stray.txt"))

        let repos = try RepoDiscovery().repos(in: base)

        #expect(repos.map(\.name) == ["Clone", "Worktree"])
        #expect(repos.map(\.rootURL.lastPathComponent) == ["Clone", "Worktree"])
    }

    @Test func skipsHiddenDirectories() throws {
        let base = try makeTemporaryDirectory()
        try addDirectory(".hidden", in: base, git: .directory)
        try addDirectory("Visible", in: base, git: .directory)

        let repos = try RepoDiscovery().repos(in: base)

        #expect(repos.map(\.name) == ["Visible"])
    }

    @Test func sortsCaseInsensitivelyByName() throws {
        let base = try makeTemporaryDirectory()
        try addDirectory("beta", in: base, git: .directory)
        try addDirectory("Alpha", in: base, git: .directory)
        try addDirectory("gamma", in: base, git: .directory)

        let repos = try RepoDiscovery().repos(in: base)

        #expect(repos.map(\.name) == ["Alpha", "beta", "gamma"])
    }

    @Test func missingScanDirectoryThrows() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForemanCoreTests-missing-\(UUID().uuidString)")

        #expect(throws: (any Error).self) {
            try RepoDiscovery().repos(in: missing)
        }
    }

    @Test func repoIDIsTheAbsolutePathWithoutATrailingSlash() {
        let repo = Repo(
            name: "Thing",
            rootURL: URL(fileURLWithPath: "/Users/dev/Development/Thing/", isDirectory: true),
        )

        #expect(repo.id == RepoID(rawValue: "/Users/dev/Development/Thing"))
    }
}
