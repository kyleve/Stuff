import Foundation

/// One coherent scan publication for badges, live flight notices, and reviews.
public struct DataIssueScanResult: Sendable {
    public let revision: UUID
    public let issues: [any DataIssue]
    public let reviews: [GPSCorrectionReview]
    /// Historical flights remain visible after a correction proposal is dismissed.
    public let completedFlights: [FlightAssessment]
    public let nextReassessmentAt: Date?

    public init(
        revision: UUID,
        issues: [any DataIssue],
        reviews: [GPSCorrectionReview],
        completedFlights: [FlightAssessment],
        nextReassessmentAt: Date?,
    ) {
        self.revision = revision
        self.issues = issues
        self.reviews = reviews
        self.completedFlights = completedFlights
        self.nextReassessmentAt = nextReassessmentAt
    }
}
