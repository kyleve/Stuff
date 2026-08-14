import PeriscopeCore

/// Structured events for `WidgetSnapshotStore`'s read path.
@LogScope("WidgetSnapshotStore")
enum WidgetSnapshotStoreLog {
    @LogEvent("unreadable-snapshot", level: .warning)
    struct UnreadableSnapshot {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Discarded an unreadable widget snapshot file: \(description)"
        }
    }
}
