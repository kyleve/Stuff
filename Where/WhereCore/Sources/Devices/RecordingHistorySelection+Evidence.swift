import Foundation
import RegionKit

extension RecordingHistorySelection {
    /// Resolved control inputs and all competing observations needed to assess a geographic
    /// correction. A preview cannot start from winners alone: the correction can change them.
    struct Evidence: Hashable {
        struct Control: Hashable {
            let selection: RecordingControlSelection.Segment
            let declaredDays: Days
        }

        let observations: [RecordingObservation]
        let visibleSampleIDs: Set<LocationSample.ID>
        let controls: [Control]
        let places: [RecordingPlace]

        func clipped(to period: RecordingPeriod) throws -> Self {
            let context = try RecordingPeriod(
                start: period.start.addingTimeInterval(-RecordingEvidencePolicy.evidencePadding),
                end: period.end.addingTimeInterval(RecordingEvidencePolicy.evidencePadding),
            )
            let observations = observations.filter { context.contains($0.sample.timestamp) }
            return try Self(
                observations: observations,
                visibleSampleIDs: visibleSampleIDs.intersection(observations.map(\.sample.id)),
                controls: controls.compactMap { control in
                    control.selection.period.intersection(period).map { .init(
                        selection: .init(
                            period: $0,
                            resolution: control.selection.resolution,
                            sourceChoiceIDs: control.selection.sourceChoiceIDs,
                        ),
                        declaredDays: control.declaredDays,
                    ) }
                },
                places: places.compactMap { place in
                    guard let overlap = place.validity.intersection(context) else { return nil }
                    return try RecordingPlace(
                        id: place.id,
                        kind: place.kind,
                        coordinate: place.coordinate,
                        validity: overlap,
                    )
                },
            )
        }
    }

    func replacingGeography(_ replacements: [LocationSample.ID: Set<Region>]) throws -> Self {
        let observations = try evidence.observations.map { observation in
            guard let regions = replacements[observation.sample.id] else { return observation }
            return try RecordingObservation(
                sample: observation.sample,
                recordingDay: observation.recordingDay,
                geography: .init(
                    knownRegions: regions.subtracting([.other]),
                    includesUnknownPresence: regions.contains(.other),
                ),
            )
        }
        return try Self.resolve(evidence: .init(
            observations: observations,
            visibleSampleIDs: evidence.visibleSampleIDs,
            controls: evidence.controls,
            places: evidence.places,
        ), version: policyVersion)
    }

    func attributedSamples() throws -> [AttributedLocationSample] {
        try contributions.map { observation in
            guard let day = observation.recordingDay.day else {
                throw DataCompatibilityError.incompleteRecord
            }
            return AttributedLocationSample(
                sample: observation.sample,
                regions: observation.geography.presence,
                day: .recording(day),
            )
        }
    }
}
