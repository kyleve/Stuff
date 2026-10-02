import Foundation
import IdentityKit

/// One coherent scan publication for badges, live flight notices, and reviews.
public struct DataIssueScanResult: Sendable {
    /// Identity of one computed publication. Cache hits retain it; a fresh scan replaces it.
    /// This is not a persisted sample-attribution revision.
    public typealias Revision = TypedID<DataIssueScanResult>

    public let revision: Revision
    public let issues: [any DataIssue]
    public let reviews: [GPSCorrectionReview]
    public let nextReassessmentAt: Date?

    public init(
        revision: Revision,
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
