import Foundation

/// Everything Ledger persists as JSON: just the refresh interval. Identity
/// comes from the Cursor session token (auto-detected or pasted), and any
/// pasted token lives in the Keychain — never in this plaintext file.
public struct LedgerConfiguration: Codable, Equatable, Sendable {
    /// Seconds between automatic refreshes.
    public var refreshInterval: TimeInterval

    public init(refreshInterval: TimeInterval) {
        self.refreshInterval = refreshInterval
    }

    /// The configuration a fresh install starts from: refreshing every 15
    /// minutes.
    public static let initial = LedgerConfiguration(refreshInterval: 15 * 60)
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
