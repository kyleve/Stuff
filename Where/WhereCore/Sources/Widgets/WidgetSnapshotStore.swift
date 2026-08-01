import Foundation
import PeriscopeCore
import WhereSurface

/// Reads and writes the widgets' published `WidgetSnapshot` as a small JSON
/// file in the App Group container shared by the app and the widget extension.
/// Every access is coordinated across processes, and writes atomically replace
/// the authoritative artifact.
///
/// Only the app process writes (after each committed store change, via
/// `WidgetCenterTimelineRefresher`); the widget process only reads. This is
/// deliberately not SwiftData: the payload is one already-aggregated value,
/// so a plain `Codable` file avoids SwiftData container startup in short-lived
/// processes and keeps the app as the only CloudKit synchronizer.
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

    /// Coordinate and atomically replace the published snapshot so another
    /// process never reads a half-written file.
    public func write(_ snapshot: WidgetSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try WhereSurfaceFileCoordinator().write(data, to: fileURL)
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
        do {
            guard let data = try WhereSurfaceFileCoordinator().read(from: fileURL)
            else { return nil }
            return try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        } catch {
            Self.logger(attachments: [.error(error, name: "read-error")]) {
                .unreadableSnapshot(description: error.localizedDescription)
            }
            return nil
        }
    }

    private static let logger = WhereLog.widgets(WidgetSnapshotStoreLog.self)
}
