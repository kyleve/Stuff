import Foundation

/// Persists the rolling list of ``SpendSample``s as JSON, pruning old points.
///
/// Only a couple of weeks are needed (the furthest baseline is the start of the
/// current week), so the file stays small. A missing file is the legitimate
/// first-run state (empty history); a file that exists but can't be decoded
/// throws rather than silently resetting.
public struct SpendHistoryStore: Sendable {
    private let fileURL: URL

    /// Samples older than this are pruned on save — comfortably longer than the
    /// oldest baseline the deltas need (start of the current week).
    public static let retention: TimeInterval = 14 * 24 * 60 * 60

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("history.json")
    }

    /// The production store, alongside the configuration under
    /// `~/Library/Application Support/com.stuff.ledger/`.
    public static func applicationSupport() -> SpendHistoryStore {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return SpendHistoryStore(directory: base.appendingPathComponent("com.stuff.ledger"))
    }

    public func load() throws -> [SpendSample] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([SpendSample].self, from: data)
    }

    public func save(_ samples: [SpendSample]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        let data = try JSONEncoder().encode(samples)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Drops samples older than ``retention`` relative to `now`.
    public func pruned(_ samples: [SpendSample], now: Date) -> [SpendSample] {
        let cutoff = now.addingTimeInterval(-Self.retention)
        return samples.filter { $0.timestamp >= cutoff }
    }
}
