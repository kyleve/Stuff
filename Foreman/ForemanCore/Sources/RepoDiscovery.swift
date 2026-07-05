import Foundation
import Observation

/// Stable identifier for a repository: its canonical absolute path.
///
/// A typed wrapper (rather than a raw `String`) so config keys and worker
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

/// A git repository as found on disk by ``RepoDiscovery/scan(_:)`` — pure
/// identity (name + root), before it becomes a live ``Repo`` in the tree.
public struct ScannedRepo: Hashable, Identifiable, Sendable {
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

/// Finds git repositories one level below the scan directory and holds the
/// resulting ``Repo`` objects — the tree's "many repos" node.
///
/// ``rescan(in:)`` reuses existing `Repo` instances by id (so a live worker
/// survives a rescan), creates new ones through the injected factory, and
/// stops + drops repos that vanished from the scan.
@MainActor
@Observable
public final class RepoDiscovery {
    /// The discovered repositories, sorted by name.
    public private(set) var repos: [Repo] = []

    private static let logger = ForemanLog.channel(.repoDiscovery)

    private let makeRepo: @MainActor (ScannedRepo) -> Repo
    /// Vanished repos whose worker hasn't exited yet. Retained so the exit
    /// bookkeeping (state transition, log footer) still lands; purged once
    /// dead on the next rescan.
    @ObservationIgnored private var draining: [Repo] = []

    /// `makeRepo` builds the live `Repo` (worker, saved state, wiring) for a
    /// newly discovered repository — the owning tree injects it.
    public init(makeRepo: @escaping @MainActor (ScannedRepo) -> Repo) {
        self.makeRepo = makeRepo
    }

    /// Re-lists `directory`, updating ``repos``. Throws if the directory
    /// can't be listed (missing, unreadable, …) — existing repos are kept in
    /// that case, so a transient failure doesn't tear down live workers.
    public func rescan(in directory: URL) throws {
        let scanned = try Self.scan(directory)

        var existing: [RepoID: Repo] = [:]
        for repo in repos {
            existing[repo.id] = repo
        }

        repos = scanned.map { found in
            existing.removeValue(forKey: found.id) ?? makeRepo(found)
        }

        draining.removeAll { !$0.worker.state.isLive }
        for (_, vanished) in existing where vanished.worker.state.isLive {
            Self.logger.info("Stopping worker for vanished repo \(vanished.id.rawValue)")
            vanished.worker.stop()
            draining.append(vanished)
        }
    }

    /// The pure directory listing: subdirectories of `directory` containing
    /// a `.git` entry — directory for a normal clone, file for worktrees and
    /// submodules — sorted by name. Hidden subdirectories are skipped;
    /// nested repositories are not searched. Throws if `directory` can't be
    /// listed.
    public static func scan(_ directory: URL) throws -> [ScannedRepo] {
        let fileManager = FileManager.default
        let entries = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
        )

        let repos = entries.compactMap { entry -> ScannedRepo? in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: entry.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  fileManager.fileExists(atPath: entry.appendingPathComponent(".git").path)
            else { return nil }
            return ScannedRepo(name: entry.lastPathComponent, rootURL: entry.standardizedFileURL)
        }
        return repos.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
