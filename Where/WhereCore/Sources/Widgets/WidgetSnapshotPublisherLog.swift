import PeriscopeCore

/// Structured events for `WidgetSnapshotPublisher`. A publish records the day
/// and region count; a build failure surfaces as `.error`.
enum WidgetSnapshotPublisherLog: LogEvent {
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
