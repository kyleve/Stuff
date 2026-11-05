import RegionKit

extension RecordingObservation {
    /// The common input boundary for saved history and immutable choice previews. Corrections
    /// retain specific geography, and saved calendar context resolves before source selection.
    static func history(
        samples: [LocationSample],
        corrections: [SampleAttributionRevision],
        controls: RecordingControlSnapshot,
        catalog: any RegionAttributing,
        version: DataSemanticsVersion,
    ) throws -> [Self] {
        var winners: [LocationSample.ID: SampleAttributionRevision] = [:]
        for revision in corrections {
            if let current = winners[revision.sampleID],
               !SampleAttributionRevision.newer(revision, than: current) { continue }
            winners[revision.sampleID] = revision
        }
        return try samples.filter(\.source.isGPS).map { sample in
            let regions = winners[sample.id]?.replacementRegions
                ?? [catalog.region(at: sample.coordinate)]
            return try Self(
                sample: sample,
                recordingDay: RecordingCalendarResolver.assignment(
                    for: sample,
                    decisions: controls.calendarContexts,
                    version: version,
                ),
                geography: RecordingGeography(
                    knownRegions: regions.subtracting([.other]),
                    includesUnknownPresence: regions.contains(.other),
                ),
            )
        }
    }
}
