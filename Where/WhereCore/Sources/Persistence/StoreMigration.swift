import Foundation
import SwiftData

/// A one-time, idempotent data migration run once per device at store open.
///
/// Migrations are registered in `StoreMigrations.all` and executed in ascending
/// `version` order by `SwiftDataStore.runPendingMigrations(calendar:)`; a
/// persisted marker (App-Group `UserDefaults`, keyed
/// `SwiftDataStore.migrationVersionKey`) records the highest version applied so
/// each runs at most once per device. Because CloudKit syncs the migrated rows
/// between devices and every migration must be **idempotent** and deterministic,
/// a per-device marker is safe: re-running a migration a second device already
/// applied is a no-op.
///
/// This is the seam for future one-off data fixes — add a new type with the next
/// `version`, append it to `StoreMigrations.all`, and it runs on next launch.
public protocol StoreMigration: Sendable {
    /// Strictly increasing across the registry; also the value written to the
    /// applied-version marker once this migration commits.
    var version: Int { get }
    /// Short human-readable label for the log line.
    var name: String { get }
    /// Mutate `context` in place. Runs inside its own write transaction (saved by
    /// the runner); throwing rolls this migration back and leaves the marker
    /// un-bumped so it retries next launch. Must be idempotent — safe to run on a
    /// store another device already migrated (rows arrive via CloudKit).
    func migrate(_ context: ModelContext, calendar: Calendar) throws
}

/// The ordered registry of data migrations, applied lowest `version` first.
enum StoreMigrations {
    static let all: [any StoreMigration] = [
        CalendarDayMigration(),
    ]
}
