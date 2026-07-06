import Foundation

/// Removes a repository copy Foreman created: a `git worktree` (via
/// `git worktree remove`) or a full `git clone` (moved to the Trash).
///
/// Split behind a protocol so ``ForemanServices/removeCopy(at:)`` can be
/// tested without shelling out to `git` or moving files to the user's Trash.
public protocol RepoCopyRemoving: Sendable {
    /// Removes the worktree checked out at `path`, whose main repository is at
    /// `parentRepoPath`. Throws with a human-readable reason on failure.
    func removeWorktree(at path: URL, parentRepoPath: URL) throws
    /// Removes a full clone at `path` (moved to the Trash). Throws on failure.
    func removeClone(at path: URL) throws
}

/// Production remover: shells out to `git worktree remove` for worktrees and
/// moves clones to the Trash via `FileManager` (recoverable, unlike a hard
/// delete). GUI apps don't inherit the shell `PATH`, so `git` is located at
/// its known install paths.
public struct SystemRepoCopyRemover: RepoCopyRemoving {
    /// Where `git` installs, checked in order.
    static let gitSearchPaths = [
        "/usr/bin/git",
        "/opt/homebrew/bin/git",
        "/usr/local/bin/git",
    ]

    public init() {}

    public func removeWorktree(at path: URL, parentRepoPath: URL) throws {
        try runGit(["-C", parentRepoPath.path, "worktree", "remove", "--force", path.path])
    }

    public func removeClone(at path: URL) throws {
        try FileManager.default.trashItem(at: path, resultingItemURL: nil)
    }

    /// A `git` invocation that failed, carrying the command's stderr as its
    /// message so the reason isn't swallowed.
    struct GitError: Error, LocalizedError {
        let message: String
        var errorDescription: String? {
            message
        }
    }

    private func runGit(_ arguments: [String]) throws {
        guard let git = Self.gitSearchPaths
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map({ URL(fileURLWithPath: $0) })
        else {
            throw GitError(
                message: "git executable not found in \(Self.gitSearchPaths.joined(separator: ", "))",
            )
        }

        let process = Process()
        process.executableURL = git
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        // Read to EOF (which lands at exit) before waiting, so a chatty git
        // can't deadlock on a full pipe.
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw GitError(
                message: stderr.isEmpty
                    ? "git exited with status \(process.terminationStatus)"
                    : stderr,
            )
        }
    }
}
