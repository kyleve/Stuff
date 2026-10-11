import Foundation

/// One coherent scan publication for badges, live flight notices, and reviews.
public struct DataIssueScanResult: Sendable {
    public let revision: UUID
    public let issues: [any DataIssue]
    public let reviews: [GPSCorrectionReview]
    public let nextReassessmentAt: Date?

    public init(
        revision: UUID,
        issues: [any DataIssue],
        reviews: [GPSCorrectionReview],
        nextReassessmentAt: Date?,
    ) {
        self.revision = revision
        self.issues = issues
        self.reviews = reviews
        self.nextReassessmentAt = nextReassessmentAt
    }
}
