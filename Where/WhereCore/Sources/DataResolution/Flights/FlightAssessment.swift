import Foundation

/// A derived flight on one recording installation's trajectory. Missing arrival
/// evidence remains unresolved; neither silence nor a calendar rollover lands it.
public struct FlightAssessment: Identifiable, Hashable, Sendable {
    /// Samples recorded before installation identities existed have their own track.
    public enum RecordingSource: Hashable, Sendable {
        case device(RecordingDeviceID)
        case legacy
    }

    public enum Reassessment: Hashable, Sendable {
        case at(Date)
        case whenEvidenceChanges

        /// Optional only at the timer boundary: evidence-driven work needs no timer.
        public var scheduledDate: Date? {
            switch self {
                case let .at(date): date
                case .whenEvidenceChanges: nil
            }
        }
    }

    public struct ID: Hashable, Sendable {
        public let recordingSource: RecordingSource
        public let departureSampleID: UUID

        public init(recordingSource: RecordingSource, departureSampleID: UUID) {
            self.recordingSource = recordingSource
            self.departureSampleID = departureSampleID
        }
    }

    /// Ground confirmation is independent of how precisely landing can be dated.
    public enum Arrival: Hashable, Sendable {
        case observedGround(firstObservedAt: Date, confirmedAt: Date)
        case uncertainTiming(lastSupportedTravelAt: Date, firstObservedAt: Date, confirmedAt: Date)

        public var firstGroundAt: Date {
            switch self {
                case let .observedGround(first, _), let .uncertainTiming(_, first, _): first
            }
        }

        public var confirmedAt: Date {
            switch self {
                case let .observedGround(_, confirmation),
                     let .uncertainTiming(_, _, confirmation): confirmation
            }
        }

        public var isTimingUncertain: Bool {
            switch self {
                case .observedGround: false
                case .uncertainTiming: true
            }
        }
    }

    /// Positive evidence of travel; gaps between these intervals remain unknown.
    public struct TravelInterval: Hashable, Sendable {
        public enum Kind: Hashable, Sendable { case observedMotion, displacement }
        public let start: Date
        public let end: Date
        public let kind: Kind

        public init(start: Date, end: Date, kind: Kind) {
            precondition(start <= end, "Travel evidence must be ordered")
            self.start = start
            self.end = end
            self.kind = kind
        }
    }

    public enum Progress: Hashable, Sendable {
        /// Recent cruise observations support the live-flight presentation.
        case flightLikely
        /// Arrival is unconfirmed; stale observations never establish landing.
        case awaitingArrival
        /// Positive ground observations confirm the trip ended, with explicit timing quality.
        case completed(arrival: Arrival)

        public var arrival: Arrival? {
            switch self {
                case let .completed(arrival): arrival
                case .flightLikely, .awaitingArrival: nil
            }
        }
    }

    public let id: ID
    public let startedAt: Date
    public let lastObservationAt: Date
    public let lastFlightAt: Date
    public let airborneSampleIDs: Set<UUID>
    public let groundSampleIDs: Set<UUID>
    public let peakSpeedKMH: Double
    public let progress: Progress
    public let inferredEndpoints: [FlightEndpointInference]
    public let supportedIntervals: [TravelInterval]

    public var lastSupportedTravelAt: Date {
        supportedIntervals.reduce(startedAt) { max($0, $1.end) }
    }

    /// Coalesced display intervals never bridge an unsupported recording gap.
    public var supportedPeriods: [DateInterval] {
        var periods: [DateInterval] = []
        for interval in supportedIntervals.sorted(by: { $0.start < $1.start }) {
            if let previous = periods.last, interval.start <= previous.end {
                periods[periods.count - 1] = DateInterval(
                    start: previous.start,
                    end: max(previous.end, interval.end),
                )
            } else {
                periods.append(DateInterval(start: interval.start, end: interval.end))
            }
        }
        return periods
    }

    public var isPending: Bool {
        switch progress {
            case .flightLikely, .awaitingArrival: true
            case .completed: false
        }
    }

    public init(
        id: ID,
        startedAt: Date,
        lastObservationAt: Date,
        lastFlightAt: Date,
        airborneSampleIDs: Set<UUID>,
        groundSampleIDs: Set<UUID>,
        peakSpeedKMH: Double,
        progress: Progress,
        inferredEndpoints: [FlightEndpointInference],
        supportedIntervals: [TravelInterval],
    ) {
        precondition(!supportedIntervals.isEmpty, "A flight requires positive travel evidence")
        self.id = id
        self.startedAt = startedAt
        self.lastObservationAt = lastObservationAt
        self.lastFlightAt = lastFlightAt
        self.airborneSampleIDs = airborneSampleIDs
        self.groundSampleIDs = groundSampleIDs
        self.peakSpeedKMH = peakSpeedKMH
        self.progress = progress
        self.inferredEndpoints = inferredEndpoints
        self.supportedIntervals = supportedIntervals
    }

    /// Inclusive days supported by observed motion or corroborated displacement.
    /// Later ground evidence cannot fill an unsupported gap with flight days.
    public func completedDays(in calendar: Calendar) -> Set<CalendarDay> {
        guard !isPending else { return [] }
        return supportedIntervals.reduce(into: Set<CalendarDay>()) { days, interval in
            days.formUnion(CalendarDay(from: interval.start, in: calendar)
                .days(through: CalendarDay(from: interval.end, in: calendar)))
        }
    }

    /// The live-flight presentation expires after the latest cruise evidence becomes
    /// stale. This deadline is not an arrival delay: observed ground dwell completes
    /// a flight as soon as its evidence qualifies, including before this deadline.
    public var reassessment: Reassessment {
        switch progress {
            case .flightLikely: .at(lastFlightAt.addingTimeInterval(
                    GPSCorrectionPolicy.Presentation.liveFlightFreshnessInterval,
                ))
            case .awaitingArrival, .completed: .whenEvidenceChanges
        }
    }
}
