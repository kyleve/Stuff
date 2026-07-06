@_spi(Testing) import ForemanCore
import Foundation
import Testing

/// Exercises the production remover against real `git` in a temp repo (never
/// the user's real repos). The clone path really trashes via `FileManager`, so
/// those tests locate the volume-appropriate Trash and clean up the moved item
/// afterwards rather than leaving it behind.
struct RepoCopyRemoverTests {
    @Test func removesARealWorktree() throws {
        let base = try makeTemporaryDirectory()
        let repo = base.appendingPathComponent("Main", isDirectory: true)
        try makeGitRepoWithCommit(at: repo)

        let worktree = base.appendingPathComponent("Copy", isDirectory: true)
        try git(["-C", repo.path, "worktree", "add", "-b", "task", worktree.path])
        #expect(FileManager.default.fileExists(atPath: worktree.path))
        #expect(FileManager.default
            .fileExists(atPath: worktree.appendingPathComponent(".git").path))

        try SystemRepoCopyRemover().removeWorktree(at: worktree, parentRepoPath: repo)

        #expect(!FileManager.default.fileExists(atPath: worktree.path))
        let list = try gitOutput(["-C", repo.path, "worktree", "list"])
        #expect(!list.contains(worktree.path))
    }

    @Test func worktreeRemovalSurfacesGitFailure() throws {
        let base = try makeTemporaryDirectory()
        let repo = base.appendingPathComponent("Main", isDirectory: true)
        try makeGitRepoWithCommit(at: repo)

        // A directory that isn't a registered worktree — git refuses, and the
        // reason must surface rather than be swallowed.
        let notAWorktree = base.appendingPathComponent("Nope", isDirectory: true)
        try FileManager.default.createDirectory(at: notAWorktree, withIntermediateDirectories: true)

        #expect(throws: (any Error).self) {
            try SystemRepoCopyRemover().removeWorktree(at: notAWorktree, parentRepoPath: repo)
        }
    }

    @Test func removesACloneToTheTrash() throws {
        let base = try makeTemporaryDirectory()
        // A unique name so the trashed item can't collide (and thus be renamed),
        // which keeps cleanup deterministic.
        let name = "Clone-\(UUID().uuidString)"
        let clone = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: clone.appendingPathComponent(".git"),
            withIntermediateDirectories: true,
        )

        // Where this volume trashes items, so we can remove the moved copy and
        // not litter the Trash.
        let trashDirectory = try FileManager.default.url(
            for: .trashDirectory,
            in: .userDomainMask,
            appropriateFor: clone,
            create: false,
        )
        let trashedItem = trashDirectory.appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: trashedItem) }

        try SystemRepoCopyRemover().removeClone(at: clone)

        // Gone from its original spot, and moved (not hard-deleted) to the Trash.
        #expect(!FileManager.default.fileExists(atPath: clone.path))
        #expect(FileManager.default.fileExists(atPath: trashedItem.path))
    }

    @Test func cloneRemovalSurfacesAMissingItem() throws {
        let base = try makeTemporaryDirectory()
        let missing = base.appendingPathComponent("Nope", isDirectory: true)

        #expect(throws: (any Error).self) {
            try SystemRepoCopyRemover().removeClone(at: missing)
        }
    }

    // MARK: - Git helpers

    private func makeGitRepoWithCommit(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try git(["-C", url.path, "init", "-q"])
        try git(["-C", url.path, "config", "user.email", "test@example.com"])
        try git(["-C", url.path, "config", "user.name", "Test"])
        try Data("hello\n".utf8).write(to: url.appendingPathComponent("README.md"))
        try git(["-C", url.path, "add", "."])
        try git(["-C", url.path, "commit", "-q", "-m", "init"])
    }

    @discardableResult
    private func git(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func gitOutput(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
