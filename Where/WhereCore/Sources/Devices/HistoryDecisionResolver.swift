import Foundation

/// Resolves causal choices per elementary interval. A descendant replaces an ancestor only
/// where both apply. Missing dependencies never become an implicitly observed revision prefix.
public enum HistoryDecisionResolver {
    public enum Resolution: Hashable, Sendable {
        case automatic
        case selected(RecordingDeviceID)
        case conflict(Set<HistoryDecision.ID>)
        case incomplete(Set<HistoryDecision.ID>)
    }

    public struct Segment: Hashable, Sendable {
        public let period: RecordingPeriod
        public let resolution: Resolution
        public let effectiveDecisions: Set<HistoryDecision.ID>
    }

    public enum ValidationError: Error, Equatable {
        case conflictingIdentity(HistoryDecision.ID)
        case unsupportedMajor(HistoryDecision.ID)
        case emptyScope(HistoryDecision.ID)
        case inconsistentScope(HistoryDecision.ID)
        case cycle(HistoryDecision.ID)
        case invalidPredecessors(HistoryDecision.ID)
    }

    public static func resolve(
        _ decisions: [HistoryDecision],
        within query: RecordingPeriod,
        version: DataSemanticsVersion,
    ) throws -> [Segment] {
        for decision in decisions {
            guard decision.version.major == version.major else {
                throw ValidationError.unsupportedMajor(decision.id)
            }
            if case let .recordingDay(deviceID, day) = decision.scope {
                guard CalendarDay(iso: day.iso8601) == day else {
                    throw ValidationError.inconsistentScope(decision.id)
                }
                if case let .select(selected) = decision.action, selected != deviceID {
                    throw ValidationError.inconsistentScope(decision.id)
                }
            }
        }
        do {
            return try CausalPeriodResolver<HistoryDecision>.resolve(decisions, within: query)
                .map { segment in
                    let resolution: Resolution = switch segment.resolution {
                        case .absent, .agreed(.automatic): .automatic
                        case let .agreed(.select(deviceID)): .selected(deviceID)
                        case let .conflict(identities): .conflict(identities)
                        case let .incomplete(identities): .incomplete(identities)
                    }
                    return Segment(
                        period: segment.period,
                        resolution: resolution,
                        effectiveDecisions: segment.effectiveOperations,
                    )
                }
        } catch let error as CausalPeriodResolver<HistoryDecision>.ValidationError {
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
