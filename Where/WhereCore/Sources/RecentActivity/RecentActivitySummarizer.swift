import Foundation
import PeriscopeCore
import RegionKit

/// One attributed reading in a recent-activity window: when the device was
/// somewhere, which tracked region that coordinate fell in, and the raw
/// coordinate. The raw unit the summarizer collapses into
/// `RecentActivitySegment`s before handing them to the generator.
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

/// A contiguous stretch the device spent in one region: the region, the first
/// (`start`) and last (`end`) reading times of the run, and a representative
/// coordinate (the arrival reading's). Produced by collapsing consecutive
/// same-region readings so the generator sees dwell spans — how long each stay
/// lasted — rather than every ping. `start == end` for a single-reading run.
public struct RecentActivitySegment: Hashable, Sendable {
    public let region: Region
    public let start: Date
    public let end: Date
    public let coordinate: Coordinate

    public init(region: Region, start: Date, end: Date, coordinate: Coordinate) {
        self.region = region
        self.start = start
        self.end = end
        self.coordinate = coordinate
    }
}

/// The structured input a `ActivitySummaryGenerating` turns into prose: the
/// window it covers plus the region segments within it, oldest first.
public struct RecentActivityInput: Hashable, Sendable {
    public let interval: DateInterval
    public let segments: [RecentActivitySegment]

    public init(interval: DateInterval, segments: [RecentActivitySegment]) {
        self.interval = interval
        self.segments = segments
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
/// window, attributes each to a `Region`, condenses consecutive same-region
/// readings into dwell segments, and hands the structured input to an injected
/// generator. Failures (an unavailable model, a generation error) propagate so
/// the caller can surface an honest state.
public actor RecentActivitySummarizer {
    /// Upper bound on the number of region segments handed to the generator.
    /// Long windows (e.g. the year so far) can hold thousands of readings;
    /// keeping only the most recent segments bounds the prompt so it fits the
    /// on-device model's context.
    public static let defaultSegmentLimit = 60

    private let store: any WhereStore
    private let attributor: any RegionAttributing
    private let generator: any ActivitySummaryGenerating
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let segmentLimit: Int
    private var history: LocationHistoryReader {
        LocationHistoryReader(store: store)
    }

    private static let logger = WhereLog.recentActivity(RecentActivitySummarizerLog.self)

    init(
        store: any WhereStore,
        attributor: any RegionAttributing,
        generator: any ActivitySummaryGenerating,
        calendar: Calendar,
        now: @escaping @Sendable () -> Date,
        segmentLimit: Int,
    ) {
        self.store = store
        self.attributor = attributor
        self.generator = generator
        self.calendar = calendar
        self.now = now
        self.segmentLimit = segmentLimit
    }

    /// Summarize the tracked locations in `window`. Returns `.empty` when
    /// nothing was recorded in the window; otherwise attributes each sample to a
    /// region, condenses consecutive same-region readings into dwell segments,
    /// and asks the generator for prose. Throws on read failure, an unavailable
    /// model, or a generation error.
    public func summary(for window: RecentActivityWindow) async throws -> RecentActivitySummary {
        let interval = window.interval(now: now(), calendar: calendar)
        let samples = try await history.samples(in: interval)
        guard !samples.isEmpty else {
            Self.logger { .skippedNoSamples }
            return .empty
        }
        let segments = Self.logger.measure(.attribute, budget: .seconds(1)) {
            let stops = samples.map { sample in
                RecentActivityStop(
                    timestamp: sample.timestamp,
                    region: attributor.region(at: sample.coordinate),
                    coordinate: sample.coordinate,
                )
            }
            return Self.segments(from: stops, limit: segmentLimit)
        }
        let text = try await Self.logger.measure(.generate) {
            try await generator.summarize(
                RecentActivityInput(interval: interval, segments: segments),
            )
        }
        Self.logger { .generated(segmentCount: segments.count) }
        return .summary(text)
    }

    /// Collapse consecutive readings attributed to the same region into one
    /// segment spanning the run's first-to-last reading, then keep only the most
    /// recent `limit` segments. The run-length collapse preserves dwell time
    /// (how long each stay lasted) while the hard cap keeps a long, fast-moving
    /// window within the prompt budget. Input is assumed oldest-first (the store
    /// sorts ascending).
    private static func segments(
        from stops: [RecentActivityStop],
        limit: Int,
    ) -> [RecentActivitySegment] {
        precondition(limit > 0, "The segment limit must be positive.")
        var segments: [RecentActivitySegment] = []
        for stop in stops {
            let lastIndex = segments.count - 1
            if lastIndex >= 0, segments[lastIndex].region == stop.region {
                // Same region as the run in progress: extend its end time,
                // keeping the arrival time and coordinate.
                let run = segments[lastIndex]
                segments[lastIndex] = RecentActivitySegment(
                    region: run.region,
                    start: run.start,
                    end: stop.timestamp,
                    coordinate: run.coordinate,
                )
            } else {
                segments.append(RecentActivitySegment(
                    region: stop.region,
                    start: stop.timestamp,
                    end: stop.timestamp,
                    coordinate: stop.coordinate,
                ))
            }
        }
        return segments.count > limit ? Array(segments.suffix(limit)) : segments
    }
}
