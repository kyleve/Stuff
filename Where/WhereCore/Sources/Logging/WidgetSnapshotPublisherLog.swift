import PeriscopeCore

/// Structured events and spans for `WidgetSnapshotPublisher`.
@LogScope("WidgetSnapshotPublisher")
enum WidgetSnapshotPublisherLog {
    enum SpanName: Hashable {
        case publish
    }

    @LogEvent("published", level: .info)
    struct Published {
        @LogField("day", exposure: .restricted, kind: .dateTime)
        var day: String

        @LogField("region_count", exposure: .shareable, kind: .count)
        var regionCount: Int

        var message: String {
            "Published widget snapshot for \(day) (\(regionCount) region(s))"
        }

        var externalID: String? {
            WhereStoreID.day(day)
        }
    }

    @LogEvent("build-failed", level: .error)
    struct BuildFailed {
        @LogField("description", exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Failed to build widget snapshot: \(description)"
        }
    }
}
