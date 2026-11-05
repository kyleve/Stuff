import Foundation

/// Durable ignore history for one device, including elapsed periods and unresolved causal
/// branches. These are automatic-eligibility controls, not a claim about selected GPS history.
public struct RecordingIgnoreHistory: Hashable, Sendable {
    public let deviceID: RecordingDeviceID
    public let generationID: WhereDataGenerationID
    public let policyVersion: DataSemanticsVersion
    public let decisions: [RecordingIgnoreDecision]
    public let segments: [RecordingIgnoreResolver.Segment]
    /// Unknown controls can also affect eligibility. A caller must retain this uncertainty
    /// instead of describing the understood ignore graph as complete history.
    public let unknownControls: [VersionedHistoryRecord]

    public init(
        controls: RecordingControlSnapshot,
        deviceID: RecordingDeviceID,
        version: DataSemanticsVersion,
    ) throws {
        let decisions = controls.ignores.filter { $0.deviceID == deviceID }.sorted {
            // Stable display order does not choose a causal winner.
            if $0.periods[0].start != $1.periods[0].start {
                return $0.periods[0].start > $1.periods[0].start
            }
            return $0.id < $1.id
        }
        let periods = RecordingPeriod.union(decisions.flatMap(\.periods))
        self.deviceID = deviceID
        generationID = controls.generationID
        policyVersion = version
        self.decisions = decisions
        segments = try periods.flatMap { period in
            try RecordingIgnoreResolver.resolve(
                controls.ignores,
                for: deviceID,
                within: period,
                version: version,
            )
        }
        unknownControls = controls.requiresReview
    }
}
