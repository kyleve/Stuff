import Foundation
import LogKit
import RegionKit

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

/// Produces a natural-language summary of a look-back window of tracked
/// locations using an on-device language model. Reads the raw samples in the
/// window, attributes each to a `Region`, condenses them to region transitions,
/// and hands the structured input to an injected generator. Failures (an
/// unavailable model, a generation error) propagate so the caller can surface
/// an honest state.
public actor RecentActivitySummarizer {
    /// Upper bound on the number of region transitions handed to the generator.
    /// Long windows (e.g. the year so far) can hold thousands of readings;
    /// keeping only the most recent transitions bounds the prompt so it fits
    /// the on-device model's context.
    public static let defaultTransitionLimit = 60

    private let store: any WhereStore
    private let attributor: RegionAttributor
    private let generator: any ActivitySummaryGenerating
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let transitionLimit: Int

    private static let logger = WhereLog.channel(.recentActivitySummarizer)

    init(
        store: any WhereStore,
        attributor: RegionAttributor,
        generator: any ActivitySummaryGenerating,
        calendar: Calendar,
        now: @escaping @Sendable () -> Date,
        transitionLimit: Int,
    ) {
        self.store = store
        self.attributor = attributor
        self.generator = generator
        self.calendar = calendar
        self.now = now
        self.transitionLimit = transitionLimit
    }

    /// Summarize the tracked locations in `window`. Returns `.empty` when
    /// nothing was recorded in the window; otherwise attributes each sample to a
    /// region, condenses consecutive same-region readings into transitions, and
    /// asks the generator for prose. Throws on read failure, an unavailable
    /// model, or a generation error.
    public func summary(for window: RecentActivityWindow) async throws -> RecentActivitySummary {
        let interval = window.interval(now: now(), calendar: calendar)
        let samples = try await store.samples(in: interval)
        guard !samples.isEmpty else {
            Self.logger.info("Recent-activity summary skipped: no samples in window")
            return .empty
        }
        let stops = samples.map { sample in
            RecentActivityStop(
                timestamp: sample.timestamp,
                region: attributor.region(at: sample.coordinate),
                coordinate: sample.coordinate,
            )
        }
        let transitions = Self.condense(stops, limit: transitionLimit)
        let text = try await generator.summarize(
            RecentActivityInput(interval: interval, stops: transitions),
        )
        Self.logger.info(
            "Recent-activity summary generated from \(transitions.count) transition(s)",
        )
        return .summary(text)
    }

    /// Collapse consecutive readings attributed to the same region into a single
    /// representative stop (the first reading of each run), then keep only the
    /// most recent `limit`. Both a run-length collapse and a hard cap so a long,
    /// stationary window and a long, fast-moving one alike stay within the
    /// prompt budget. Input is assumed oldest-first (the store sorts ascending).
    private static func condense(
        _ stops: [RecentActivityStop],
        limit: Int,
    ) -> [RecentActivityStop] {
        var transitions: [RecentActivityStop] = []
        for stop in stops where transitions.last?.region != stop.region {
            transitions.append(stop)
        }
        return transitions.count > limit ? Array(transitions.suffix(limit)) : transitions
    }
}
