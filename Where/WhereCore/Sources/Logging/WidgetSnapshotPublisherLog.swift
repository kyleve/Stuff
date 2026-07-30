import PeriscopeCore

/// Structured events for `WidgetSnapshotPublisher`. A publish records the day
/// and region count; a build failure surfaces as `.error`.
enum WidgetSnapshotPublisherLog: LogEvent {
    /// Names the publisher's timed spans.
    enum SpanName: Hashable {
        /// Rebuilding the snapshot from the store and handing it to WidgetKit.
        /// Spanned here rather than in `WidgetDataReader` because the reader is
        /// only ever driven from this actor, and the WidgetKit reload the
        /// publish ends with is part of what a caller waits for. The skip paths
        /// (`refreshIfStale`, `publishAfterIngest`) are deliberately outside, so
        /// the span history counts rebuilds rather than the far more numerous
        /// times a rebuild was avoided.
        case publish
    }

    case published(day: String, regionCount: Int)
    case buildFailed(description: String)

    static let eventName = "WidgetSnapshotPublisher"

    var level: LogLevel {
        switch self {
            case .published: .info
            case .buildFailed: .error
        }
    }

    var message: String {
        switch self {
            case let .published(day, regionCount):
                "Published widget snapshot for \(day) (\(regionCount) region(s))"
            case let .buildFailed(description):
                "Failed to build widget snapshot: \(description)"
        }
    }

    var externalID: String? {
        switch self {
            case let .published(day, _): WhereStoreID.day(day)
            case .buildFailed: nil
        }
    }
}
