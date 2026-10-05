import Foundation
import RegionKit

/// An explicit, reversible decision about one GPS point in a completed flight.
/// The full review evidence is pinned so late data or a reset invalidates the decision.
public struct FlightPointCorrection: Hashable, Sendable {
    public enum Action: Hashable, Sendable {
        case includeInFlight
        case restoreGPS
    }

    public let sampleID: UUID
    public let action: Action
    public let day: CalendarDay
    public let resultingRegions: Set<Region>
    public let dataGenerationID: WhereDataGenerationID
    let evidence: SampleCorrectionProposal.Evidence
}
