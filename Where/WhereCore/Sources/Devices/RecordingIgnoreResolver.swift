/// Resolves a device's eligibility by observation time, including expired decisions and their
/// reversals. A source choice takes precedence later, at history selection, independently of sync
/// order.
public enum RecordingIgnoreResolver {
    public enum Resolution: Hashable, Sendable {
        case eligible, ignored
        case conflict(Set<RecordingIgnoreDecision.ID>)
        case incomplete(Set<RecordingIgnoreDecision.ID>)
    }

    public struct Segment: Hashable, Sendable {
        public let period: RecordingPeriod
        public let resolution: Resolution
        public let effectiveDecisions: Set<RecordingIgnoreDecision.ID>
    }

    public enum ValidationError: Error, Equatable {
        case conflictingIdentity(RecordingIgnoreDecision.ID)
        case invalidPredecessor(RecordingIgnoreDecision.ID)
        case unsupportedMajor(RecordingIgnoreDecision.ID)
        case emptyScope(RecordingIgnoreDecision.ID)
        case cycle(RecordingIgnoreDecision.ID)
        case invalidPredecessors(RecordingIgnoreDecision.ID)
    }

    public static func resolve(
        _ decisions: [RecordingIgnoreDecision],
        for deviceID: RecordingDeviceID,
        within query: RecordingPeriod,
        version: DataSemanticsVersion,
    ) throws -> [Segment] {
        var records: [RecordingIgnoreDecision.ID: RecordingIgnoreDecision] = [:]
        for decision in decisions {
            if let old = records[decision.id],
               old != decision { throw ValidationError.conflictingIdentity(decision.id) }
            records[decision.id] = decision
        }
        let relevant = decisions.filter { $0.deviceID == deviceID }
        for decision in relevant {
            try decision.validate()
            guard decision.version.major == version.major
            else { throw ValidationError.unsupportedMajor(decision.id) }
            for predecessor in decision.predecessors {
                if let record = records[predecessor], record.deviceID != deviceID {
                    throw ValidationError.invalidPredecessor(decision.id)
                }
            }
        }
        do {
            return try CausalPeriodResolver<RecordingIgnoreDecision>
                .resolve(relevant, within: query).map { segment in
                    let resolution: Resolution = switch segment.resolution {
                        case .absent, .agreed(.eligible): .eligible
                        case .agreed(.ignored): .ignored
                        case let .conflict(identities): .conflict(identities)
                        case let .incomplete(identities): .incomplete(identities)
                    }
                    return Segment(
                        period: segment.period,
                        resolution: resolution,
                        effectiveDecisions: segment.effectiveOperations,
                    )
                }
        } catch let error as CausalPeriodResolver<RecordingIgnoreDecision>.ValidationError {
            switch error {
                case let .conflictingIdentity(identity): throw ValidationError
                .conflictingIdentity(identity)
                case let .emptyScope(identity): throw ValidationError.emptyScope(identity)
                case let .cycle(identity): throw ValidationError.cycle(identity)
                case let .invalidPredecessors(identity): throw ValidationError
                .invalidPredecessors(identity)
            }
        }
    }
}
