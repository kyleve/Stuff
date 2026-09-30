import Foundation

/// A derived flight on one recording installation's trajectory. Missing arrival
/// evidence remains unresolved; neither silence nor a calendar rollover lands it.
public struct FlightAssessment: Identifiable, Hashable, Sendable {
    public struct ID: Hashable, Sendable {
        public let recordingDeviceID: RecordingDeviceID?
        public let departureSampleID: UUID

        public init(recordingDeviceID: RecordingDeviceID?, departureSampleID: UUID) {
            self.recordingDeviceID = recordingDeviceID
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
    public var nextReassessmentAt: Date? {
        switch progress {
            case .flightLikely: lastFlightAt.addingTimeInterval(
                    GPSCorrectionPolicy.Presentation.liveFlightFreshnessInterval,
                )
            case .awaitingArrival, .completed: nil
        }
    }
}
