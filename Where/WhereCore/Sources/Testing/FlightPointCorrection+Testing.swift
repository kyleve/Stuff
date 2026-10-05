#if DEBUG
    import Foundation
    import RegionKit

    extension FlightPointCorrection {
        @_spi(Testing)
        public init(
            sampleID: UUID,
            action: Action,
            day: CalendarDay,
            resultingRegions: Set<Region>,
        ) {
            let proposal = SampleCorrectionProposal(
                kind: .flight,
                day: DayPresence(day: day, regions: resultingRegions),
                resultingRegions: resultingRegions,
                edits: [],
            )
            self.init(
                sampleID: sampleID,
                action: action,
                day: day,
                resultingRegions: resultingRegions,
                dataGenerationID: proposal.dataGenerationID,
                evidence: proposal.evidence,
            )
        }
    }
#endif
