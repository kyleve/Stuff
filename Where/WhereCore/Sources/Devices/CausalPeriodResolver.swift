import Foundation

/// The resolver uses the operation's own interval type. Finite controls cannot acquire an
/// ongoing scope; places can resolve their complete history without an artificial query end.
protocol CausalInterval: Hashable, Sendable {
    var start: Date { get }
    var upperBound: Date? { get }
    init(causalStart: Date, upperBound: Date?) throws
    func validate() throws
    func contains(_ instant: Date) -> Bool
    func intersection(_ other: Self) -> Self?
}

extension RecordingPeriod: CausalInterval {
    var upperBound: Date? {
        end
    }

    init(causalStart: Date, upperBound: Date?) throws {
        guard let upperBound else { throw ValidationError.invalidBounds }
        try self.init(start: causalStart, end: upperBound)
    }
}

extension RecordingInterval: CausalInterval {
    var upperBound: Date? {
        end
    }

    init(causalStart: Date, upperBound: Date?) throws {
        try self.init(start: causalStart, end: upperBound)
    }
}

/// Shared causal topology for immutable controls. Domain resolvers validate versions and scope
/// meaning, then use this resolver without collapsing identities from different control types.
protocol CausalPeriodOperation: Hashable, Sendable {
    associatedtype ID: Hashable, Sendable, Comparable
    associatedtype Action: Hashable, Sendable
    associatedtype Period: CausalInterval
    var id: ID { get }
    var periods: [Period] { get }
    func action(at instant: Date) -> Action
    var actionChangeInstants: [Date] { get }
    var predecessorIDs: [ID] { get }
    var predecessors: Set<ID> { get }
}

extension CausalPeriodOperation {
    var actionChangeInstants: [Date] {
        []
    }
}

enum CausalPeriodResolver<Operation: CausalPeriodOperation> {
    enum Resolution: Hashable {
        case absent
        case agreed(Operation.Action)
        case conflict(Set<Operation.ID>)
        case incomplete(Set<Operation.ID>)
    }

    struct Segment: Hashable {
        let period: Operation.Period
        let resolution: Resolution
        let effectiveOperations: Set<Operation.ID>
    }

    enum ValidationError: Error, Equatable {
        case conflictingIdentity(Operation.ID)
        case emptyScope(Operation.ID)
        case cycle(Operation.ID)
        case invalidPredecessors(Operation.ID)
    }

    private struct Knowledge {
        var ancestors: Set<Operation.ID> = []
        var missing: Set<Operation.ID> = []
    }

    static func resolve(
        _ operations: [Operation],
        within query: Operation.Period,
    ) throws -> [Segment] {
        try query.validate()
        var records: [Operation.ID: Operation] = [:]
        for operation in operations.sorted(by: { $0.id < $1.id }) {
            if let existing = records[operation.id], existing != operation {
                throw ValidationError.conflictingIdentity(operation.id)
            }
            guard !operation.periods.isEmpty else { throw ValidationError.emptyScope(operation.id) }
            guard operation.predecessorIDs == operation.predecessors.sorted() else {
                throw ValidationError.invalidPredecessors(operation.id)
            }
            for period in operation.periods {
                try period.validate()
            }
            records[operation.id] = operation
        }
        var knowledge: [Operation.ID: Knowledge] = [:]
        for operationID in records.keys.sorted() {
            knowledge[operationID] = try ancestors(
                of: operationID,
                records: records,
                visiting: [],
                cache: &knowledge,
            )
        }
        let boundaries = Set([query.start] + [query.upperBound].compactMap(\.self)
            + records.values.flatMap { operation in
                operation.periods.compactMap { $0.intersection(query) }.flatMap {
                    [$0.start] + [$0.upperBound].compactMap(\.self)
                }
                    + operation.actionChangeInstants.filter { query.contains($0) }
            }).sorted()
        return try boundaries.enumerated().filter { query.contains($0.element) }
            .map { index, start in
                let end = index + 1 < boundaries.count ? boundaries[index + 1] : query.upperBound
                let active = records.values.filter { $0.periods.contains { $0.contains(start) } }
                let missing = active.reduce(into: Set<Operation.ID>()) { result, operation in
                    result.formUnion(knowledge[operation.id]?.missing ?? [])
                }
                let maximal = active.filter { candidate in
                    !active.contains { knowledge[$0.id]?.ancestors.contains(candidate.id) == true }
                }
                let effective = Set(maximal.map(\.id))
                let resolution: Resolution = if !missing.isEmpty {
                    .incomplete(missing)
                } else if Set(maximal.map { $0.action(at: start) }).count > 1 {
                    .conflict(effective)
                } else if let operation = maximal.first {
                    .agreed(operation.action(at: start))
                } else {
                    .absent
                }
                return try Segment(
                    period: Operation.Period(causalStart: start, upperBound: end),
                    resolution: resolution,
                    effectiveOperations: effective,
                )
            }
    }

    private static func ancestors(
        of operationID: Operation.ID,
        records: [Operation.ID: Operation],
        visiting: Set<Operation.ID>,
        cache: inout [Operation.ID: Knowledge],
    ) throws -> Knowledge {
        if let known = cache[operationID] { return known }
        guard !visiting.contains(operationID) else { throw ValidationError.cycle(operationID) }
        guard let record = records[operationID] else { return Knowledge(missing: [operationID]) }
        var result = Knowledge()
        for predecessor in record.predecessors.sorted() {
            let prior = try ancestors(
                of: predecessor,
                records: records,
                visiting: visiting.union([operationID]),
                cache: &cache,
            )
            result.ancestors.insert(predecessor)
            result.ancestors.formUnion(prior.ancestors)
            result.missing.formUnion(prior.missing)
        }
        cache[operationID] = result
        return result
    }
}
