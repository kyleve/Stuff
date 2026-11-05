/// Resolves a place's historical definition, including ongoing homes. Unresolved edits supply no
/// automatic
/// corroboration and remain visible to the caller for review.
public enum RecordingPlaceResolver {
    public enum Resolution: Hashable, Sendable {
        case absent
        case place(RecordingPlace)
        case conflict(Set<RecordingPlaceDecision.ID>)
        case incomplete(Set<RecordingPlaceDecision.ID>)
    }

    public struct Segment: Hashable, Sendable {
        public let period: RecordingInterval
        public let resolution: Resolution
        public let effectiveDecisions: Set<RecordingPlaceDecision.ID>
    }

    public enum ValidationError: Error, Equatable {
        case conflictingIdentity(RecordingPlaceDecision.ID)
        case invalidPredecessor(RecordingPlaceDecision.ID)
        case unsupportedMajor(RecordingPlaceDecision.ID)
    }

    public static func resolve(
        _ decisions: [RecordingPlaceDecision],
        for placeID: RecordingPlace.ID,
        within query: RecordingInterval,
        version: DataSemanticsVersion,
    ) throws -> [Segment] {
        var records: [RecordingPlaceDecision.ID: RecordingPlaceDecision] = [:]
        for decision in decisions {
            if let old = records[decision.id],
               old != decision { throw ValidationError.conflictingIdentity(decision.id) }
            records[decision.id] = decision
        }
        let relevant = decisions.filter { $0.placeID == placeID }
        for decision in relevant {
            try decision.validate()
            guard decision.version.major == version.major
            else { throw ValidationError.unsupportedMajor(decision.id) }
            for predecessor in decision.predecessors {
                if let record = records[predecessor], record.placeID != placeID {
                    throw ValidationError.invalidPredecessor(decision.id)
                }
            }
        }
        return try CausalPeriodResolver<RecordingPlaceDecision>.resolve(relevant, within: query)
            .map { segment in
                let resolution: Resolution = switch segment.resolution {
                    case .absent, .agreed(.remove): .absent
                    case let .agreed(.set(kind, coordinate)):
                        try .place(RecordingPlace(
                            id: placeID,
                            kind: kind,
                            coordinate: coordinate,
                            validity: segment.period,
                        ))
                    case let .conflict(identities): .conflict(identities)
                    case let .incomplete(identities): .incomplete(identities)
                }
                return Segment(
                    period: segment.period,
                    resolution: resolution,
                    effectiveDecisions: segment.effectiveOperations,
                )
            }
    }

    public static func resolve(
        _ decisions: [RecordingPlaceDecision],
        for placeID: RecordingPlace.ID,
        within query: RecordingPeriod,
        version: DataSemanticsVersion,
    ) throws -> [Segment] {
        try resolve(decisions, for: placeID, within: RecordingInterval(query), version: version)
    }
}
