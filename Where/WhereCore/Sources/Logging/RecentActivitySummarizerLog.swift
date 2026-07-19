import PeriscopeCore

/// Structured events for `RecentActivitySummarizer`, the on-device look-back
/// summary. Both outcomes are `.info` — a skip (no samples) and a successful
/// generation.
enum RecentActivitySummarizerLog: LogEvent {
    /// Names the summarizer's timed spans.
    enum SpanName: Hashable {
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
