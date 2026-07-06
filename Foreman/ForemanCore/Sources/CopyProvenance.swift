import Foundation

/// Records that a repository is a copy Foreman created on behalf of the MCP
/// server — a `git worktree` or a full `git clone` of a parent repo.
///
/// Persisted on ``RepoConfiguration`` so a copy can be badged in the UI and
/// removed the right way: a worktree via `git worktree remove`, a clone by
/// moving it to the Trash. Ordinary discovered repositories have no
/// provenance (`nil`).
public struct CopyProvenance: Codable, Equatable, Sendable {
    /// How the copy was created. The two kinds have different removal paths,
    /// so this is a single value rather than a loose `isWorktree` flag.
    public enum Kind: String, Codable, Sendable {
        case worktree
        case clone
    }

    public var kind: Kind
    /// The repository the copy was made from.
    public var parentRepoID: RepoID
    /// The branch checked out in the copy.
    public var branch: String

    public init(kind: Kind, parentRepoID: RepoID, branch: String) {
        self.kind = kind
        self.parentRepoID = parentRepoID
        self.branch = branch
    }
}
