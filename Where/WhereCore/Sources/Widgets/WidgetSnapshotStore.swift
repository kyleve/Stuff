import Foundation
import PeriscopeCore

/// Reads and writes the widgets' published `WidgetSnapshot` as a small JSON
/// file in the App Group container shared by the app and the widget
/// extension. Production callers go through `AppGroupDataAccess` for verification.
///
/// Only the app process writes (after each committed store change, via
/// `WidgetCenterTimelineRefresher`); the widget process only reads. This is
/// deliberately not SwiftData: the payload is one already-aggregated value,
/// so a plain `Codable` file avoids the widget paying SwiftData container
/// startup — and keeps the user's real, CloudKit-synced store private to
/// the app's own sandbox.
struct WidgetSnapshotStore {
    /// Thrown when the App Group container can't be resolved, which means
    /// the running process is missing the
    /// `com.apple.security.application-groups` entitlement (or the group
    /// identifier is misspelled).
    struct AppGroupUnavailableError: Error {
        init() {}
    }

    private static let fileName = "widget-snapshot.json"

    /// The shared access boundary resolves the App Group; tests use temporary directories.
    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    private var fileURL: URL {
        directory.appending(path: Self.fileName)
    }

    /// Atomically replace the published snapshot. Atomic so the widget never
    /// reads a half-written file.
    func write(_ snapshot: PersistedWidgetSnapshot) throws {
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
    func read() -> PersistedWidgetSnapshot? {
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(PersistedWidgetSnapshot.self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            Self.logger.unreadableSnapshot(
                error: .restricted(.errorDetails, error),
            )
            return nil
        }
    }

    private static let logger = WhereLog.widgets(WidgetSnapshotStoreLog.self)
}
