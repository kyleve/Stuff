/// Retains the work the user entered, independently of later derived issue identifiers.
/// This is an in-memory reference, not a notification payload or permission to write history.
public struct RecordingReviewReference: Hashable, Sendable {
    public struct Context: Hashable, Sendable {
        public let historicalYear: Int
        public let query: LocationHistoryQuery

        public init(historicalYear: Int, query: LocationHistoryQuery) {
            self.historicalYear = historicalYear
            self.query = query
        }
    }

    public enum ValidationError: Error, Equatable {
        case unknownIssue
        case emptyScope
        case scopeOutsideIssue
        case scopeOutsideQuery
    }

    public let issueID: RecordingIssue.ID
    public let originalPeriods: [RecordingPeriod]
    public let context: Context
    public let scopeID: RecordingReviewSnapshot.ScopeID
    public let generationID: WhereDataGenerationID
    public let policyVersion: DataSemanticsVersion

    public init(
        issue: RecordingIssue,
        originalPeriods: [RecordingPeriod],
        context: Context,
        snapshot: RecordingReviewSnapshot,
    ) throws {
        guard snapshot.issues.contains(issue) else { throw ValidationError.unknownIssue }
        guard !originalPeriods.isEmpty else { throw ValidationError.emptyScope }
        for period in originalPeriods {
            try period.validate()
        }
        let periods = RecordingPeriod.union(originalPeriods)
        guard periods.allSatisfy({
            issue.period.start <= $0.start && $0.end <= issue.period.end
        }) else { throw ValidationError.scopeOutsideIssue }
        let queryPeriod = try context.query.recordingPeriod()
        guard periods.allSatisfy({
            queryPeriod.start <= $0.start && $0.end <= queryPeriod.end
        }) else { throw ValidationError.scopeOutsideQuery }
        issueID = issue.id
        self.originalPeriods = periods
        self.context = context
        scopeID = snapshot.scopeID
        generationID = snapshot.generationID
        policyVersion = snapshot.policyVersion
    }
}
