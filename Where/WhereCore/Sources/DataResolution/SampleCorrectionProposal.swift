import Foundation
import RegionKit

/// The exact sample edits a user reviewed, together with the evidence that must
/// still hold when they apply them. It never asserts a whole calendar day.
public struct SampleCorrectionProposal: Hashable, Sendable {
    public struct Edit: Hashable, Sendable {
        public let sampleID: UUID
        public let replacementRegions: Set<Region>

        public init(sampleID: UUID, replacementRegions: Set<Region>) {
            self.sampleID = sampleID
            self.replacementRegions = replacementRegions
        }
    }

    /// A bounded, lossless input identity; equality detects late observations,
    /// changed manual assertions, corrections, or attribution configuration.
    struct Evidence: Hashable {
        let history: LocationHistoryProjection
        let manualDays: [DayPresence]
        let primaryRegions: [Region]
        let trackedRegions: [Region]
        let driftThresholdMeters: Double
        let calendar: Calendar
        let flights: [FlightAssessment]
    }

    public let reviewID: DataIssueID
    public let day: DayPresence
    public let resultingRegions: Set<Region>
    public let edits: [Edit]
    public let dataGenerationID: WhereDataGenerationID
    let evidence: Evidence

    init(
        reviewID: DataIssueID,
        day: DayPresence,
        resultingRegions: Set<Region>,
        edits: [Edit],
        dataGenerationID: WhereDataGenerationID,
        evidence: Evidence,
    ) {
        self.reviewID = reviewID
        self.day = day
        self.resultingRegions = resultingRegions
        self.edits = edits
        self.dataGenerationID = dataGenerationID
        self.evidence = evidence
    }

    @_spi(Testing)
    public init(
        reviewID: DataIssueID,
        day: DayPresence,
        resultingRegions: Set<Region>,
        edits: [Edit],
    ) {
        self.init(
            reviewID: reviewID,
            day: day,
            resultingRegions: resultingRegions,
            edits: edits,
            dataGenerationID: .initial,
            evidence: Evidence(
                history: LocationHistoryProjection(samples: [], revisions: []),
                manualDays: [],
                primaryRegions: [],
                trackedRegions: [],
                driftThresholdMeters: 1000,
                calendar: Calendar(identifier: .gregorian),
                flights: [],
            ),
        )
    }
}
