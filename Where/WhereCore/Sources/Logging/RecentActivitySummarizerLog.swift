import PeriscopeCore

/// Structured events for `RecentActivitySummarizer`, the on-device look-back
/// summary. Both outcomes are `.info` — a skip (no samples) and a successful
/// generation.
enum RecentActivitySummarizerLog: LogEvent {
    /// Names the summarizer's timed spans.
    enum SpanName: Hashable {
        /// Attributing every reading in the window to a region and collapsing the
        /// runs into dwell segments. A point-in-polygon test per reading, and a
        /// long window holds thousands, so it's worth separating from the model
        /// call it feeds — a slow summary is otherwise assumed to be the model's
        /// fault.
        case attribute
        /// The on-device model call.
        case generate
    }

    case skippedNoSamples
    case generated(segmentCount: Int)

    static let eventName = "RecentActivitySummarizer"

    var message: String {
        switch self {
            case .skippedNoSamples:
                "Recent-activity summary skipped: no samples in window"
            case let .generated(segmentCount):
                "Recent-activity summary generated from \(segmentCount) segment(s)"
        }
    }
}
