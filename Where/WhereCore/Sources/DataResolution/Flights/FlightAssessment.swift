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

    public enum Progress: Hashable, Sendable {
        /// Recent cruise observations support the live-flight presentation.
        case flightLikely
        /// Arrival is unconfirmed; stale observations never establish landing.
        case awaitingArrival
        /// Observed ground dwell confirms arrival from its first ground anchor.
        case completed(arrivedAt: Date)
    }

    public let id: ID
    public let startedAt: Date
    public let lastObservationAt: Date
    public let lastFlightAt: Date
    public let airborneSampleIDs: Set<UUID>
    public let groundSampleIDs: Set<UUID>
    public let peakSpeedKMH: Double
    public let progress: Progress

    public init(
        id: ID,
        startedAt: Date,
        lastObservationAt: Date,
        lastFlightAt: Date,
        airborneSampleIDs: Set<UUID>,
        groundSampleIDs: Set<UUID>,
        peakSpeedKMH: Double,
        progress: Progress,
    ) {
        self.id = id
        self.startedAt = startedAt
        self.lastObservationAt = lastObservationAt
        self.lastFlightAt = lastFlightAt
        self.airborneSampleIDs = airborneSampleIDs
        self.groundSampleIDs = groundSampleIDs
        self.peakSpeedKMH = peakSpeedKMH
        self.progress = progress
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
