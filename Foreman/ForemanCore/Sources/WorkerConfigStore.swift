import Foundation

/// Everything Foreman persists: which repos have their worker enabled, each
/// repo's ``WorkerOptions``, and the global settings.
public struct ForemanConfiguration: Codable, Equatable, Sendable {
    /// Directory scanned for git repositories; `nil` means the default
    /// (`~/Development`, see ``resolvedScanDirectory``).
    public var scanDirectory: URL?
    /// Explicit `cursor-agent` executable; `nil` means auto-locate via
    /// ``CursorAgentLocator``.
    public var agentExecutable: URL?
    /// Repos whose worker should be running. Enabled workers are restarted on
    /// app launch.
    public var enabledRepoIDs: Set<RepoID>
    /// Per-repo worker options; repos absent from the map use
    /// ``WorkerOptions/standard``.
    public var repoOptions: [RepoID: WorkerOptions]

    public init(
        scanDirectory: URL?,
        agentExecutable: URL?,
        enabledRepoIDs: Set<RepoID>,
        repoOptions: [RepoID: WorkerOptions],
    ) {
        self.scanDirectory = scanDirectory
        self.agentExecutable = agentExecutable
        self.enabledRepoIDs = enabledRepoIDs
        self.repoOptions = repoOptions
    }

    /// The configuration a fresh install starts from.
    public static let initial = ForemanConfiguration(
        scanDirectory: nil,
        agentExecutable: nil,
        enabledRepoIDs: [],
        repoOptions: [:],
    )

    /// The scan directory with the `~/Development` default applied.
    public var resolvedScanDirectory: URL {
        scanDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Development")
    }

    /// Options for `repo`, falling back to ``WorkerOptions/standard`` for
    /// repos that were never customized (absence is expected, not an error).
    public func options(for repo: RepoID) -> WorkerOptions {
        repoOptions[repo] ?? .standard
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
