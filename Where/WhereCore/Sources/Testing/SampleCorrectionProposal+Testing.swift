#if DEBUG
    import Foundation
    import RegionKit

    extension SampleCorrectionProposal {
        @_spi(Testing)
        public init(
            kind: Kind,
            day: DayPresence,
            resultingRegions: Set<Region>,
            edits: [Edit],
        ) {
            self.init(
                kind: kind,
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
#endif
