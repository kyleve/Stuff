/// Reconciles original review scopes with current issues. Matching uses absolute periods, so
/// recovered logical dates and new device evidence cannot make outstanding work disappear.
public struct RecordingReviewQueue: Hashable, Sendable {
    public enum ValidationError: Error, Equatable {
        case emptyQueue
        case differentServiceScope
        case dataGenerationChanged
        case incompatiblePolicy
        case incompleteAssessment
    }

    /// Current combined context and the exact bounded periods a choice may address. Context
    /// can cross a gap between original concerns; authored periods never acquire that gap.
    public struct Item: Hashable, Sendable, Identifiable {
        public struct ID: Hashable, Sendable {
            public let issueID: RecordingIssue.ID
            public let periods: [RecordingPeriod]
        }

        public let issue: RecordingIssue
        public let periods: [RecordingPeriod]
        public let references: Set<RecordingReviewReference>

        public var id: ID {
            ID(issueID: issue.id, periods: periods)
        }
    }

    public let references: Set<RecordingReviewReference>
    public let originalPeriods: [RecordingPeriod]
    private let scopeID: RecordingReviewSnapshot.ScopeID
    private let generationID: WhereDataGenerationID
    private let requiredMajor: UInt

    public init(references: [RecordingReviewReference]) throws {
        guard let first = references.first else { throw ValidationError.emptyQueue }
        guard references.allSatisfy({ $0.scopeID == first.scopeID }) else {
            throw ValidationError.differentServiceScope
        }
        guard references.allSatisfy({ $0.generationID == first.generationID }) else {
            throw ValidationError.dataGenerationChanged
        }
        guard references.allSatisfy({ $0.policyVersion.major == first.policyVersion.major }) else {
            throw ValidationError.incompatiblePolicy
        }
        self.references = Set(references)
        originalPeriods = RecordingPeriod.union(references.flatMap(\.originalPeriods))
        scopeID = first.scopeID
        generationID = first.generationID
        requiredMajor = first.policyVersion.major
    }

    /// Only a successful assessment of every original period can return an empty queue.
    /// Failure leaves the immutable original work available for retry. Skipping is a presentation
    /// action; callers must not remove its reference or treat it as resolved.
    public func remaining(in snapshot: RecordingReviewSnapshot) throws -> [Item] {
        guard snapshot.scopeID == scopeID else { throw ValidationError.differentServiceScope }
        guard snapshot.generationID == generationID else {
            throw ValidationError.dataGenerationChanged
        }
        guard snapshot.policyVersion.major == requiredMajor else {
            throw ValidationError.incompatiblePolicy
        }
        guard snapshot.covers(originalPeriods) else { throw ValidationError.incompleteAssessment }
        return snapshot.issues.compactMap { issue in
            let periods = RecordingPeriod.union(originalPeriods.compactMap {
                $0.intersection(issue.period)
            })
            guard !periods.isEmpty else { return nil }
            let relevant = references.filter { reference in
                reference.originalPeriods.contains { $0.overlaps(issue.period) }
            }
            return Item(issue: issue, periods: periods, references: relevant)
        }
    }
}
