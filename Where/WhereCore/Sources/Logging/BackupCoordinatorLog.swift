import PeriscopeCore

/// Structured events for `BackupCoordinator`. Failing to clear a previous export
/// staging directory is degraded-but-handled housekeeping, so it logs at
/// `.warning`.
enum BackupCoordinatorLog: LogEvent {
    /// Names the coordinator's timed spans. Export and import are the longest
    /// operations in the app — whole-table reads and per-blob file I/O — and the
    /// only ones that show the user a progress bar, so they're decomposed far
    /// enough to say *which* leg the bar is stuck on. `BackupService` spans the
    /// zip/unzip and manifest legs that sit inside these.
    ///
    /// Unbudgeted, all of them: the runtime is proportional to the library, so
    /// any threshold that didn't warn on a small library would be silent on a
    /// large one. The percentiles in the span history are the yardstick here.
    enum SpanName: Hashable {
        /// A whole export: reads, blob load, archive write.
        case exportBackup
        /// The four whole-table reads plus the primary-region set.
        case exportReads
        /// Loading every evidence blob out of external storage — the leg the
        /// progress bar tracks.
        case exportBlobLoad
        /// A whole import: read the archive, then write it in one transaction.
        case importBackup
        /// The single transaction an import commits, row by row.
        case importWrite
    }

    case removePreviousExportFailed(description: String)

    static let eventName = "BackupCoordinator"

    var level: LogLevel {
        .warning
    }

    var message: String {
        switch self {
            case let .removePreviousExportFailed(description):
                "Failed to remove previous backup export directory: \(description)"
        }
    }
}
