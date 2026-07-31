import Foundation
import PeriscopeCore
import WhereSurface

/// Reads and writes the widgets' published `WidgetSnapshot` as a small JSON
/// file in the App Group container shared by the app and the widget
/// extension.
///
/// Only the app process writes (after each committed store change, via
/// `WidgetCenterTimelineRefresher`); the widget process only reads. This is
/// deliberately not SwiftData: the payload is one already-aggregated value,
/// so a plain `Codable` file avoids the widget paying SwiftData container
/// startup — and keeps the user's real, CloudKit-synced store private to
/// the app's own sandbox.
public struct WidgetSnapshotStore: Sendable {
    /// Thrown when the App Group container can't be resolved, which means
    /// the running process is missing the
    /// `com.apple.security.application-groups` entitlement (or the group
    /// identifier is misspelled).
    public struct AppGroupUnavailableError: Error {
        public init() {}
    }

    /// Directory the snapshot file lives in. Exposed via `init` so tests can
    /// point at a temp directory; production resolves the App Group via
    /// `shared()`.
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// App Group-backed store shared by the app and widget. Throws
    /// `AppGroupUnavailableError` when the container can't be resolved.
    public static func shared() throws -> WidgetSnapshotStore {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WhereSurfaceStore.appGroupIdentifier,
        ) else {
            throw AppGroupUnavailableError()
        }
        return WidgetSnapshotStore(directory: container)
    }

    private var fileURL: URL {
        directory.appending(path: WhereSurfaceStore.snapshotFileName)
    }

    /// Atomically replace the published snapshot. Atomic so the widget never
    /// reads a half-written file.
    public func write(_ snapshot: WidgetSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    /// The last published snapshot, or `nil` if nothing has been written yet
    /// or the file can't be read/decoded. A `nil` result is the widget's cue
    /// to render its placeholder/empty state.
    ///
    /// The two ways of answering `nil` are told apart in the log rather than in
    /// the return type: "nothing published yet" is the normal fresh-install path
    /// and stays quiet, while a file that exists but won't decode is a real
    /// failure and warns (see ``WidgetSnapshotStoreLog``). The empty state is
    /// still the honest thing to render either way — the next publish replaces
    /// the bad file — so the signature stays non-throwing for the widget's
    /// timeline provider.
    public func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        } catch {
            Self.logger(attachments: [.error(error, name: "decode-error")]) {
                .unreadableSnapshot(description: error.localizedDescription)
            }
            return nil
        }
    }

    private static let logger = WhereLog.widgets(WidgetSnapshotStoreLog.self)
}
