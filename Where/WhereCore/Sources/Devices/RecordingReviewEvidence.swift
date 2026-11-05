import Foundation

/// The relevant inputs from one admitted store snapshot. Equality ignores delivery order and
/// unrelated periods, but retains raw measurements, corrections, controls, and manual overlays.
public struct RecordingReviewEvidence: Hashable, Sendable {
    public let query: RecordingReviewQuery
    public let generationID: WhereDataGenerationID
    public let policyVersion: DataSemanticsVersion
    public let samples: Set<LocationSample>
    public let corrections: Set<SampleAttributionRevision>
    public let controls: RecordingControlSnapshot
    public let removals: Set<RecordingDeviceRemoval>
    public let manualDays: Set<DayPresence>
    public let primaryRegions: [PrimaryRegion]
}
