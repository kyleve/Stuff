import Foundation
import RegionKit

/// An explicit, reversible decision about one GPS point in a completed flight.
/// The full review evidence is pinned so late data or a reset invalidates the decision.
public struct FlightPointCorrection: Hashable, Sendable {
    public enum Action: Hashable, Sendable {
        case includeInFlight
        case restoreGPS
    }

    enum RegionPreview: Hashable {
        /// Foundation aggregation counts independent regional support once for the whole day.
        case resolved(Set<Region>)
        /// A recording correction can change the selected source, so assess it only on demand.
        case recording(replacement: Set<Region>)
    }

    public let sampleID: LocationSample.ID
    public let action: Action
    public let day: CalendarDay
    public let dataGenerationID: WhereDataGenerationID
    let evidence: SampleCorrectionProposal.Evidence
    let regionPreview: RegionPreview

    /// Assess this one candidate against its immutable review evidence. Preparing a flight's
    /// point list must not run a full selection for every action the user might never inspect.
    public var resultingRegions: Set<Region> {
        get throws {
            switch regionPreview {
                case let .resolved(regions): regions
                case let .recording(replacement):
                    try evidence.history.previewRegions(
                        on: day,
                        applying: [sampleID: replacement],
                        primaryRegions: Set(evidence.primaryRegions),
                        manualDays: evidence.manualDays,
                        calendar: evidence.calendar,
                    )
            }
        }
    }
}
