/// A source-choice preview and its immutable save proposal. The proposal retains the same
/// operation identity on every retry; a refreshed review creates a new proposed operation.
public enum RecordingChoiceReview: Hashable, Sendable {
    public struct Proposal: Hashable, Sendable {
        let ownerID: RecordingChoiceCoordinator.ScopeID
        public let request: RecordingChoiceRequest
        public let evidence: RecordingReviewEvidence
        public let decision: HistoryDecision
    }

    public struct Clarification: Hashable, Sendable {
        public let request: RecordingChoiceRequest
        public let evidence: RecordingReviewEvidence
        public let missingPeriods: [RecordingPeriod]
    }

    case ready(Proposal)
    case needsCalendarContext(Clarification)
    /// Complete context can establish that the chosen logical date never occurred.
    case absentRecordingDay(RecordingChoiceRequest)
}
