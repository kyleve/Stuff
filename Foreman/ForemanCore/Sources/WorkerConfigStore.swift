import Foundation

/// Everything Foreman persists for a single repository: whether its worker
/// should run, whether the user favorited it, and its ``WorkerOptions``.
///
/// One record per repo — rather than parallel maps keyed by ``RepoID`` — so
/// the enabled flag, the favorite flag, and the options can't drift apart.
public struct RepoConfiguration: Codable, Equatable, Sendable {
    /// Whether this repo's worker should be running. Enabled workers are
    /// restarted on app launch.
    public var isEnabled: Bool
    /// Whether the user pinned this repo to the top of its sidebar section.
    public var isFavorite: Bool
    /// This repo's worker options.
    public var options: WorkerOptions

    public init(isEnabled: Bool, isFavorite: Bool, options: WorkerOptions) {
        self.isEnabled = isEnabled
        self.isFavorite = isFavorite
        self.options = options
    }

    /// The record an uncustomized repo reads as: disabled, unfavorited,
    /// standard options. A repo whose state equals this needs no persisted
    /// entry — absence reads identically.
    public static let standard = RepoConfiguration(
        isEnabled: false,
        isFavorite: false,
        options: .standard,
    )
}

/// Everything Foreman persists: the per-repo records and the global settings.
public struct ForemanConfiguration: Codable, Equatable, Sendable {
    /// Directory scanned for git repositories; `nil` means the default
    /// (`~/Development`, applied by ``AppSettings/resolvedScanDirectory`` —
    /// the snapshot stores only what the user chose).
    public var scanDirectory: URL?
    /// Explicit `cursor-agent` executable; `nil` means auto-locate via
    /// ``CursorAgentLocator``.
    public var agentExecutable: URL?
    /// Per-repo persisted state, keyed by ``RepoID``. Repos absent from the
    /// map read as ``RepoConfiguration/standard`` (absence is expected, not an
    /// error).
    public var repos: [RepoID: RepoConfiguration]

    public init(
        scanDirectory: URL?,
        agentExecutable: URL?,
        repos: [RepoID: RepoConfiguration],
    ) {
        self.scanDirectory = scanDirectory
        self.agentExecutable = agentExecutable
        self.repos = repos
    }

    /// The configuration a fresh install starts from.
    public static let initial = ForemanConfiguration(
        scanDirectory: nil,
        agentExecutable: nil,
        repos: [:],
    )

    /// The persisted record for `repo`, falling back to
    /// ``RepoConfiguration/standard`` for repos that were never customized
    /// (absence is expected, not an error).
    public func configuration(for repo: RepoID) -> RepoConfiguration {
        repos[repo] ?? .standard
    }

    /// Drops `repos` entries for repositories that live under `scanDirectory`
    /// but are no longer in `discovered` — entries for deleted or renamed
    /// repos would otherwise accumulate forever. Entries *outside*
    /// `scanDirectory` are kept: they belong to another scan directory's
    /// history and re-apply when the user switches back. Returns whether
    /// anything was removed.
    public mutating func prune(discovered: Set<RepoID>, under scanDirectory: URL) -> Bool {
        let prefix = scanDirectory.standardizedFileURL.path + "/"
        let stale = repos.keys.filter { id in
            id.rawValue.hasPrefix(prefix) && !discovered.contains(id)
        }
        guard !stale.isEmpty else { return false }

        for key in stale {
            repos.removeValue(forKey: key)
        }
        return true
    }
}

/// Loads and saves the ``ForemanConfiguration`` JSON file.
///
/// A missing file is the legitimate first-launch state and loads as
/// ``ForemanConfiguration/initial``; a file that exists but can't be read or
/// decoded is corrupt and `load()` throws rather than silently resetting.
public struct WorkerConfigStore: Sendable {
    private let fileURL: URL

    /// A store whose config file is `configuration.json` inside `directory`
    /// (created on first save).
    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("configuration.json")
    }

    /// The production store, under
    /// `~/Library/Application Support/com.stuff.foreman/`. The path is
    /// deterministic (Foreman is not sandboxed), so this can't fail; the
    /// directory itself is created on first save.
    public static func applicationSupport() -> WorkerConfigStore {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return WorkerConfigStore(directory: base.appendingPathComponent("com.stuff.foreman"))
    }

    public func load() throws -> ForemanConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .initial
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(ForemanConfiguration.self, from: data)
    }

    public func save(_ configuration: ForemanConfiguration) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: fileURL, options: .atomic)
    }
}
