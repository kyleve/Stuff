import PeriscopeCore

/// Structured events and spans for `WidgetSnapshotPublisher`.
@LogScope("WidgetSnapshotPublisher")
enum WidgetSnapshotPublisherLog {
    enum SpanName: Hashable {
        case publish
    }

    @LogEvent("published", level: .info)
    struct Published {
        @LogField(exposure: .restricted, kind: .dateTime)
        var day: String

        @LogField(exposure: .shareable, kind: .count)
        var regionCount: Int

        var message: String {
            "Published widget snapshot for \(day) (\(regionCount) region(s))"
        }

        var externalID: String? {
            WhereStoreID.day(day)
        }
    }

    @LogEvent("build-failed", level: .error, version: 2)
    struct BuildFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Failed to build widget snapshot: \(error.description)"
        }
    }
}
