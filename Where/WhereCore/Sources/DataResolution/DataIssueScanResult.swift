import Foundation

/// One coherent scan publication for badges, live flight notices, and reviews.
public struct DataIssueScanResult: Sendable {
    public let revision: UUID
    /// The same snapshot's recording conflicts and full assessment policy, even when no
    /// conventional correction is actionable or all such suggestions have been dismissed.
    public let completeness: HistoryCompleteness
    public let issues: [any DataIssue]
    public let reviews: [GPSCorrectionReview]
    /// Historical flights remain visible after a correction proposal is dismissed.
    public let completedFlights: [FlightAssessment]
    public let nextReassessmentAt: Date?

    public init(
        revision: UUID,
        completeness: HistoryCompleteness,
        issues: [any DataIssue],
        reviews: [GPSCorrectionReview],
        completedFlights: [FlightAssessment],
        nextReassessmentAt: Date?,
    ) {
        self.revision = revision
        self.completeness = completeness
        self.issues = issues
        self.reviews = reviews
        self.completedFlights = completedFlights
        self.nextReassessmentAt = nextReassessmentAt
    }
}
