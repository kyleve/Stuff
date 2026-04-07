import Foundation

public struct YearDataBundle: Equatable, Sendable {
    public let year: Int
    public let locationSamples: [LocationSample]
    public let manualEntries: [ManualLogEntry]
    public let evidenceAttachments: [EvidenceAttachment]
    public let syncCheckpoint: SyncCheckpoint
    public let trackingState: TrackingState?

    public init(
        year: Int,
        locationSamples: [LocationSample],
        manualEntries: [ManualLogEntry],
        evidenceAttachments: [EvidenceAttachment],
        syncCheckpoint: SyncCheckpoint,
        trackingState: TrackingState? = nil,
    ) {
        self.year = year
        self.locationSamples = locationSamples
        self.manualEntries = manualEntries
        self.evidenceAttachments = evidenceAttachments
        self.syncCheckpoint = syncCheckpoint
        self.trackingState = trackingState
    }
}
