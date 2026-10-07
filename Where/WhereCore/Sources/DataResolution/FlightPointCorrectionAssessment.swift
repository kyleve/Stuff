import Foundation
import RegionKit

/// Offers point decisions only within a completed flight on the point's own device.
/// Manual days, duplicate conflicts, and pending-flight observations remain protected.
struct FlightPointCorrectionAssessment {
    let attributor: any RegionAttributing

    func corrections(
        day: CalendarDay,
        entries: [AttributedLocationSample],
        conflictingSampleIDs: Set<LocationSample.ID>,
        dataGenerationID: WhereDataGenerationID,
        evidence: SampleCorrectionProposal.Evidence,
    ) -> [FlightPointCorrection] {
        guard !evidence.manualDays.contains(where: \.isAuthoritative) else { return [] }
        let completed = evidence.flights.filter { !$0.isPending }
        guard !completed.isEmpty else { return [] }
        let pending = evidence.flights.filter(\.isPending)
        // Entries already belong to this calendar day. Build their shared support
        // once rather than reaggregating the whole day for every possible edit.
        let contributions = RegionContributions(
            entries: entries,
            manualRegions: evidence.manualDays.reduce(into: Set<Region>()) {
                $0.formUnion($1.regions)
            },
        )
        var seen: Set<LocationSample.ID> = []
        return entries.sorted {
            if $0.sample.timestamp != $1.sample.timestamp {
                return $0.sample.timestamp < $1.sample.timestamp
            }
            return $0.sample.id.uuidString < $1.sample.id.uuidString
        }.compactMap { entry in
            let sample = entry.sample
            guard sample.source.isGPS, seen.insert(sample.id).inserted,
                  !conflictingSampleIDs.contains(sample.id),
                  completed.contains(where: { contains(sample, in: $0) }),
                  !pending.contains(where: { contains(sample, in: $0) }) else { return nil }
            let action: FlightPointCorrection.Action = entry.regions.isEmpty
                ? .restoreGPS : .includeInFlight
            let replacement: Set<Region> = action == .restoreGPS
                ? [attributor.region(at: sample.coordinate)] : []
            return FlightPointCorrection(
                sampleID: sample.id,
                action: action,
                day: day,
                resultingRegions: contributions.replacing(sampleID: sample.id, with: replacement),
                dataGenerationID: dataGenerationID,
                evidence: evidence,
            )
        }
    }

    private func contains(_ sample: LocationSample, in flight: FlightAssessment) -> Bool {
        let source = sample.recordingDeviceID
            .map(FlightAssessment.RecordingSource.device) ?? .legacy
        guard source == flight.id.recordingSource else { return false }
        let end: Date = switch flight.progress {
            case let .completed(arrivedAt): arrivedAt
            case .flightLikely, .awaitingArrival: flight.lastObservationAt
        }
        return sample.timestamp >= flight.startedAt && sample.timestamp <= end
    }

    /// Counts support by identity so identical synced rows cannot preserve an
    /// excluded point's regions. Additive manual assertions always retain support.
    private struct RegionContributions {
        let regions: Set<Region>
        let soleRegionsBySample: [LocationSample.ID: Set<Region>]

        init(entries: [AttributedLocationSample], manualRegions: Set<Region>) {
            var contributors: [Region: Set<LocationSample.ID>] = [:]
            for entry in entries {
                for region in entry.regions {
                    contributors[region, default: []].insert(entry.sample.id)
                }
            }
            regions = Set(contributors.keys).union(manualRegions)
            var soleRegions: [LocationSample.ID: Set<Region>] = [:]
            for (region, sampleIDs) in contributors where !manualRegions.contains(region) {
                if sampleIDs.count == 1, let sampleID = sampleIDs.first {
                    soleRegions[sampleID, default: []].insert(region)
                }
            }
            soleRegionsBySample = soleRegions
        }

        func replacing(sampleID: LocationSample.ID, with replacement: Set<Region>) -> Set<Region> {
            regions.subtracting(soleRegionsBySample[sampleID] ?? []).union(replacement)
        }
    }
}
