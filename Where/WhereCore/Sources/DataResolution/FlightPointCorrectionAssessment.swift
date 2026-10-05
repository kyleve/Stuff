import Foundation
import RegionKit

/// Offers point decisions only within a completed flight on the point's own device.
/// Manual days, duplicate conflicts, and pending-flight observations remain protected.
struct FlightPointCorrectionAssessment {
    let attributor: any RegionAttributing
    let calendar: Calendar

    func corrections(
        day: CalendarDay,
        entries: [AttributedLocationSample],
        conflictingSampleIDs: Set<UUID>,
        dataGenerationID: WhereDataGenerationID,
        evidence: SampleCorrectionProposal.Evidence,
    ) -> [FlightPointCorrection] {
        guard !evidence.manualDays.contains(where: \.isAuthoritative) else { return [] }
        let completed = evidence.flights.filter { !$0.isPending }
        let pending = evidence.flights.filter(\.isPending)
        var seen: Set<UUID> = []
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
            let corrected = entries.map {
                $0.sample.id == sample.id
                    ? AttributedLocationSample(sample: $0.sample, regions: replacement) : $0
            }
            let result = DayAggregator(calendar: calendar, timeZone: calendar.timeZone)
                .report(for: day.year, history: corrected, manualDays: evidence.manualDays)
                .days.first { $0.day == day }?.regions ?? []
            return FlightPointCorrection(
                sampleID: sample.id,
                action: action,
                day: day,
                resultingRegions: result,
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
}
