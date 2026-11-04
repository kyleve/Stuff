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
        case cycle(HistoryDecision.ID)
    }

    private struct Knowledge {
        var ancestors: Set<HistoryDecision.ID> = []
        var missing: Set<HistoryDecision.ID> = []
    }

    public static func resolve(
        _ decisions: [HistoryDecision],
        within query: RecordingPeriod,
        version: DataSemanticsVersion,
    ) throws -> [Segment] {
        var records: [HistoryDecision.ID: HistoryDecision] = [:]
        for decision in decisions.sorted(by: { $0.id < $1.id }) {
            if let existing = records[decision.id], existing != decision {
                throw ValidationError.conflictingIdentity(decision.id)
            }
            guard decision.version.major == version.major else {
                throw ValidationError.unsupportedMajor(decision.id)
            }
            guard !decision.periods.isEmpty else { throw ValidationError.emptyScope(decision.id) }
            records[decision.id] = decision
        }
        var knowledge: [HistoryDecision.ID: Knowledge] = [:]
        for decisionID in records.keys.sorted() {
            knowledge[decisionID] = try ancestors(
                of: decisionID,
                records: records,
                visiting: [],
                cache: &knowledge,
            )
        }
        let boundaries = Set([query.start, query.end] + records.values.flatMap { decision in
            decision.periods.compactMap { $0.intersection(query) }.flatMap { [$0.start, $0.end] }
        }).sorted()
        return try zip(boundaries, boundaries.dropFirst()).map { start, end in
            let active = records.values.filter { decision in
                decision.periods.contains { $0.contains(start) }
            }
            let missing = active.reduce(into: Set<HistoryDecision.ID>()) { result, decision in
                result.formUnion(knowledge[decision.id]?.missing ?? [])
            }
            let maximal = active.filter { candidate in
                !active.contains { other in
                    knowledge[other.id]?.ancestors.contains(candidate.id) == true
                }
            }
            let effective = Set(maximal.map(\.id))
            let resolution: Resolution = if !missing.isEmpty {
                .incomplete(missing)
            } else if Set(maximal.map(\.action)).count > 1 {
                .conflict(effective)
            } else if let decision = maximal.first {
                switch decision.action {
                    case .automatic: .automatic
                    case let .select(deviceID): .selected(deviceID)
                }
            } else {
                .automatic
            }
            return try Segment(
                period: RecordingPeriod(start: start, end: end),
                resolution: resolution,
                effectiveDecisions: effective,
            )
        }
    }

    private static func ancestors(
        of decisionID: HistoryDecision.ID,
        records: [HistoryDecision.ID: HistoryDecision],
        visiting: Set<HistoryDecision.ID>,
        cache: inout [HistoryDecision.ID: Knowledge],
    ) throws -> Knowledge {
        if let known = cache[decisionID] { return known }
        guard !visiting.contains(decisionID) else { throw ValidationError.cycle(decisionID) }
        guard let record = records[decisionID] else { return Knowledge(missing: [decisionID]) }
        var result = Knowledge()
        for predecessor in record.predecessors.sorted() {
            let prior = try ancestors(
                of: predecessor,
                records: records,
                visiting: visiting.union([decisionID]),
                cache: &cache,
            )
            result.ancestors.insert(predecessor)
            result.ancestors.formUnion(prior.ancestors)
            result.missing.formUnion(prior.missing)
        }
        cache[decisionID] = result
        return result
    }
}
