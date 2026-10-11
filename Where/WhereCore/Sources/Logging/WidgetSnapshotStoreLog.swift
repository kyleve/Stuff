import PeriscopeCore

/// Structured events for `WidgetSnapshotStore`'s read path.
@LogScope("WidgetSnapshotStore")
enum WidgetSnapshotStoreLog {
    @LogEvent("unreadable-snapshot", level: .warning, version: 2)
    struct UnreadableSnapshot {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Discarded an unreadable widget snapshot file: \(error.description)"
        }
    }
}
