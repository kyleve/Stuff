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
        case flightLikely
        case awaitingArrival
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

    /// Time alone changes freshness, never the evidence needed to correct samples.
    public var nextReassessmentAt: Date? {
        switch progress {
            case .flightLikely: lastFlightAt.addingTimeInterval(Self.freshnessInterval)
            case .awaitingArrival, .completed: nil
        }
    }

    static let freshnessInterval: TimeInterval = 30 * 60
}
