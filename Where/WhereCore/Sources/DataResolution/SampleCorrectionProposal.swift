import Foundation
import RegionKit

/// The exact sample edits a user reviewed, together with the evidence that must
/// still hold when they apply them. It never asserts a whole calendar day.
public struct SampleCorrectionProposal: Hashable, Sendable {
    /// Only GPS corrections can produce sample edits.
    public enum Kind: Hashable, Sendable {
        case flight
        case borderDrift

        func reviewID(for day: CalendarDay) -> DataIssueID {
            switch self {
                case .flight: .flightDay(day: day)
                case .borderDrift: .borderDrift(day: day)
            }
        }
    }

    public struct Edit: Hashable, Sendable {
        public let sampleID: LocationSample.ID
        public let replacementRegions: Set<Region>

        public init(sampleID: LocationSample.ID, replacementRegions: Set<Region>) {
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

    public let kind: Kind
    public var reviewID: DataIssueID {
        kind.reviewID(for: day.day)
    }

    public let day: DayPresence
    public let resultingRegions: Set<Region>
    public let edits: [Edit]
    public let dataGenerationID: WhereDataGenerationID
    let evidence: Evidence
}
