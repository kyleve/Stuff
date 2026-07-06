import Foundation
import LogKit

/// One attributed reading in a recent-activity window: when the device was
/// somewhere, which tracked region that coordinate fell in, and the raw
/// coordinate. The unit fed to the summary generator.
public struct RecentActivityStop: Hashable, Sendable {
    public let timestamp: Date
    public let region: Region
    public let coordinate: Coordinate

    public init(timestamp: Date, region: Region, coordinate: Coordinate) {
        self.timestamp = timestamp
        self.region = region
        self.coordinate = coordinate
    }
}

/// The structured input a `ActivitySummaryGenerating` turns into prose: the
/// window it covers plus the attributed stops within it, oldest first.
public struct RecentActivityInput: Hashable, Sendable {
    public let interval: DateInterval
    public let stops: [RecentActivityStop]

    public init(interval: DateInterval, stops: [RecentActivityStop]) {
        self.interval = interval
        self.stops = stops
    }
}

/// The outcome of a recent-activity summary. Distinguishes a real generated
/// summary from an empty window so the UI can show a distinct "nothing tracked"
/// state rather than an empty string that reads like a failure.
public enum RecentActivitySummary: Sendable, Equatable {
    case summary(String)
    case empty
}

/// Why an on-device summary can't be produced right now. Mirrors the reasons
/// the system language model reports so the UI can guide the user (e.g. enable
/// Apple Intelligence) instead of showing a generic error.
public enum ActivitySummaryUnavailableReason: Hashable, Sendable {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unknown
}

/// Thrown by a generator when the on-device model is unavailable. A typed error
/// (not a benign default) so the summary surfaces an honest, actionable state.
public struct ActivitySummaryUnavailableError: Error, Hashable, Sendable {
    public let reason: ActivitySummaryUnavailableReason

    public init(reason: ActivitySummaryUnavailableReason) {
        self.reason = reason
    }
}

/// Seam over the text generator so `RecentActivitySummarizer` can be unit-tested
/// with a stub while production wires the on-device Foundation Models generator.
/// Implementations throw `ActivitySummaryUnavailableError` when the model can't
/// run and rethrow any generation failure — never a silent empty summary.
public protocol ActivitySummaryGenerating: Sendable {
    func summarize(_ input: RecentActivityInput) async throws -> String
}

/// Produces a natural-language summary of the last 24 hours of tracked
/// locations using an on-device language model. Reads the raw samples in the
/// window, attributes each to a `Region`, and hands the structured input to an
/// injected generator. Failures (an unavailable model, a generation error)
/// propagate so the caller can surface an honest state.
public actor RecentActivitySummarizer {
    /// The look-back window the summary covers.
    public static let window: TimeInterval = 24 * 60 * 60

    private let store: any WhereStore
    private let attributor: RegionAttributor
    private let generator: any ActivitySummaryGenerating
    private let now: @Sendable () -> Date

    private static let logger = WhereLog.channel(.recentActivitySummarizer)

    init(
        store: any WhereStore,
        attributor: RegionAttributor,
        generator: any ActivitySummaryGenerating,
        now: @escaping @Sendable () -> Date,
    ) {
        self.store = store
        self.attributor = attributor
        self.generator = generator
        self.now = now
    }

    /// Summarize the last 24 hours of tracked locations. Returns `.empty` when
    /// nothing was recorded in the window; otherwise attributes each sample to a
    /// region and asks the generator for prose. Throws on read failure, an
    /// unavailable model, or a generation error.
    public func summary() async throws -> RecentActivitySummary {
        let end = now()
        let interval = DateInterval(start: end.addingTimeInterval(-Self.window), end: end)
        let samples = try await store.samples(in: interval)
        guard !samples.isEmpty else {
            Self.logger.info("Recent-activity summary skipped: no samples in the last 24h")
            return .empty
        }
        let stops = samples.map { sample in
            RecentActivityStop(
                timestamp: sample.timestamp,
                region: attributor.region(at: sample.coordinate),
                coordinate: sample.coordinate,
            )
        }
        let text = try await generator.summarize(
            RecentActivityInput(interval: interval, stops: stops),
        )
        Self.logger.info("Recent-activity summary generated from \(stops.count) stop(s)")
        return .summary(text)
    }
}
