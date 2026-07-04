import Foundation

/// Stable identifier for a repository: its canonical absolute path.
///
/// A typed wrapper (rather than a raw `String`) so config keys and supervisor
/// lookups can't silently typo into an untracked id. `RawRepresentable` with a
/// `String` raw value makes it `CodingKeyRepresentable`, so dictionaries keyed
/// by `RepoID` encode as plain JSON objects.
public struct RepoID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(rootURL: URL) {
        rawValue = rootURL.standardizedFileURL.path
    }
}

/// A git repository found by ``RepoDiscovery``.
public struct Repo: Hashable, Identifiable, Sendable {
    /// The directory name, e.g. `Stuff`.
    public let name: String
    /// Absolute file URL of the repository root.
    public let rootURL: URL

    public var id: RepoID {
        RepoID(rootURL: rootURL)
    }

    public init(name: String, rootURL: URL) {
        self.name = name
        self.rootURL = rootURL
    }
}

/// Finds git repositories one level below a scan directory.
///
/// A subdirectory counts as a repository when it contains a `.git` entry —
/// directory for a normal clone, file for worktrees and submodules. Hidden
/// subdirectories are skipped; nested repositories are not searched.
public struct RepoDiscovery: Sendable {
    public init() {}

    /// Returns the repositories directly inside `directory`, sorted by name.
    /// Throws if `directory` can't be listed (missing, unreadable, …).
    public func repos(in directory: URL) throws -> [Repo] {
        let fileManager = FileManager.default
        let entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
        )

        let repos = entries.compactMap { entry -> Repo? in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: entry.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  fileManager.fileExists(atPath: entry.appendingPathComponent(".git").path)
            else { return nil }
            return Repo(name: entry.lastPathComponent, rootURL: entry.standardizedFileURL)
        }
        return repos.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
