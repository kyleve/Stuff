import Foundation

/// Everything Ledger persists as JSON: the team-member email and the refresh
/// interval. The Admin API key is deliberately absent — it lives in the
/// Keychain, never in this plaintext file.
public struct LedgerConfiguration: Codable, Equatable, Sendable {
    /// The team member whose spend to display; `nil` until the user sets it.
    public var teamMemberEmail: String?
    /// Seconds between automatic refreshes.
    public var refreshInterval: TimeInterval

    public init(teamMemberEmail: String?, refreshInterval: TimeInterval) {
        self.teamMemberEmail = teamMemberEmail
        self.refreshInterval = refreshInterval
    }

    /// The configuration a fresh install starts from: no email yet, refreshing
    /// every 15 minutes.
    public static let initial = LedgerConfiguration(
        teamMemberEmail: nil,
        refreshInterval: 15 * 60,
    )
}

/// Loads and saves the ``LedgerConfiguration`` JSON file.
///
/// A missing file is the legitimate first-launch state and loads as
/// ``LedgerConfiguration/initial``; a file that exists but can't be read or
/// decoded is corrupt and `load()` throws rather than silently resetting.
public struct LedgerConfigStore: Sendable {
    private let fileURL: URL

    /// A store whose config file is `configuration.json` inside `directory`
    /// (created on first save).
    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("configuration.json")
    }

    /// The production store, under
    /// `~/Library/Application Support/com.stuff.ledger/`. The path is
    /// deterministic (Ledger is not sandboxed), so this can't fail; the
    /// directory itself is created on first save.
    public static func applicationSupport() -> LedgerConfigStore {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return LedgerConfigStore(directory: base.appendingPathComponent("com.stuff.ledger"))
    }

    public func load() throws -> LedgerConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .initial
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(LedgerConfiguration.self, from: data)
    }

    public func save(_ configuration: LedgerConfiguration) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: fileURL, options: .atomic)
    }
}
