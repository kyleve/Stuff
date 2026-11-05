import Foundation

/// Historical place definitions, including removals and unresolved edits. Each entry keeps
/// its actual validity periods; display ordering never selects a causal winner.
public struct RecordingPlaceHistory: Hashable, Sendable {
    public struct Entry: Hashable, Sendable {
        public let placeID: RecordingPlace.ID
        public let decisions: [RecordingPlaceDecision]
        public let segments: [RecordingPlaceResolver.Segment]
    }

    public let generationID: WhereDataGenerationID
    public let policyVersion: DataSemanticsVersion
    public let entries: [Entry]
    /// Unknown controls remain separate from understood definitions and can prevent their use.
    /// An empty place list does not establish that shared control history is complete.
    public let unknownControls: [VersionedHistoryRecord]

    public init(controls: RecordingControlSnapshot, version: DataSemanticsVersion) throws {
        generationID = controls.generationID
        policyVersion = version
        let groups = Dictionary(grouping: controls.places, by: \.placeID)
        entries = try groups.map { placeID, values in
            let decisions = values.sorted {
                if $0.periods[0].start != $1.periods[0].start {
                    return $0.periods[0].start > $1.periods[0].start
                }
                return $0.id < $1.id
            }
            let periods = RecordingInterval.union(decisions.flatMap(\.periods))
            let segments = try periods.flatMap { period in
                try RecordingPlaceResolver.resolve(
                    controls.places,
                    for: placeID,
                    within: period,
                    version: version,
                )
            }
            return Entry(placeID: placeID, decisions: decisions, segments: segments)
        }.sorted { $0.placeID < $1.placeID }
        unknownControls = controls.requiresReview
    }
}
