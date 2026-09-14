import Foundation
import RegionKit

/// Combines trajectory and local boundary evidence into exact, reversible GPS
/// edits. Unknown observations and user assertions always retain their support.
struct SampleCorrectionAssessment {
    let attributor: any RegionAttributing
    let calendar: Calendar

    func reviews(
        reads: DataIssueReads,
        primaryRegions: [Region],
        driftThresholdMeters: Double,
        now: Date,
    ) -> [GPSCorrectionReview] {
        let flights = FlightTrajectoryAnalyzer().analyze(
            samples: reads.history.rawSamples,
            now: now,
        )
        let byDay = Dictionary(grouping: reads.history.samples) {
            CalendarDay(from: $0.sample.timestamp, in: calendar)
        }
        let revisionsBySample = Dictionary(grouping: reads.history.revisions, by: \.sampleID)
        return byDay.keys.filter { $0.year == reads.report.year }.sorted().compactMap { day in
            let start = day.startOfDay(in: calendar)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
                assertionFailure("Cannot derive a calendar day's successor")
                return nil
            }
            let contextStart = start.addingTimeInterval(-24 * 60 * 60)
            let contextEnd = end.addingTimeInterval(24 * 60 * 60)
            let contextDays = CalendarDay(from: contextStart, in: calendar)
                .days(through: CalendarDay(from: contextEnd, in: calendar))
            let context = contextDays.flatMap { byDay[$0] ?? [] }.filter {
                $0.sample.timestamp >= contextStart && $0.sample.timestamp < contextEnd
            }.sorted { $0.sample.timestamp < $1.sample.timestamp }
            return review(
                day: day,
                entries: byDay[day] ?? [],
                flights: flights,
                reads: reads,
                primaryRegions: primaryRegions,
                driftThresholdMeters: driftThresholdMeters,
                context: LocationHistoryProjection(
                    samples: context,
                    revisions: context.flatMap { revisionsBySample[$0.sample.id] ?? [] }
                        .sorted { $0.id.uuidString < $1.id.uuidString },
                ),
            )
        }
    }

    private func review(
        day: CalendarDay,
        entries: [AttributedLocationSample],
        flights: [FlightAssessment],
        reads: DataIssueReads,
        primaryRegions: [Region],
        driftThresholdMeters: Double,
        context: LocationHistoryProjection,
    ) -> GPSCorrectionReview? {
        let start = day.startOfDay(in: calendar)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            assertionFailure("Cannot derive the end of a Gregorian day")
            return nil
        }
        let dayFlights = flights.filter { flight in
            let last: Date = switch flight.progress {
                case let .completed(arrivedAt): arrivedAt
                case .flightLikely, .awaitingArrival: flight.lastObservationAt
            }
            return flight.startedAt < end && last >= start
        }
        let presence = reads.report.days.first { $0.day == day }
            ?? DayPresence(day: day, regions: [])
        let points = entries.map { SampleCorrectionPoint(sample: $0.sample, regions: $0.regions) }
        let reviewID: DataIssueID = dayFlights
            .isEmpty ? .borderDrift(day: day) : .flightDay(day: day)
        if let pending = dayFlights.last(where: {
            switch $0.progress {
                case .flightLikely, .awaitingArrival: true
                case .completed: false
            }
        }) {
            return GPSCorrectionReview(
                id: reviewID,
                day: presence,
                points: points,
                state: .pending(pending),
                flights: dayFlights,
            )
        }

        let boundaryEvidence = Dictionary(grouping: context.samples.filter {
            $0.sample.source.isGPS && usable($0.sample)
        }, by: \.sample.recordingDeviceID)
        let airborne = dayFlights.reduce(into: Set<UUID>()) { $0.formUnion($1.airborneSampleIDs) }
        let allAirborne = flights.reduce(into: Set<UUID>()) { $0.formUnion($1.airborneSampleIDs) }
        let manuals = reads.manualDays.filter { $0.day == day }
        var edits: [SampleCorrectionProposal.Edit] = []
        // An explicit whole-day assertion is authoritative. Keep it intact and
        // offer only the informational completed-flight state beneath it.
        if !manuals.contains(where: \.isAuthoritative) {
            for entry in entries where entry.sample.source.isGPS && !entry.regions.isEmpty {
                if airborne.contains(entry.sample.id) {
                    edits.append(.init(sampleID: entry.sample.id, replacementRegions: []))
                } else if let region = boundaryReplacement(
                    for: entry,
                    neighbors: boundaryEvidence[entry.sample.recordingDeviceID] ?? [],
                    airborne: allAirborne,
                    primaryRegions: primaryRegions,
                    threshold: driftThresholdMeters,
                ), entry.regions != [region] {
                    edits.append(.init(sampleID: entry.sample.id, replacementRegions: [region]))
                }
            }
        }
        edits.sort { $0.sampleID.uuidString < $1.sampleID.uuidString }
        let replacement = Dictionary(uniqueKeysWithValues: edits.map { (
            $0.sampleID,
            $0.replacementRegions,
        ) })
        let corrected = entries.map {
            AttributedLocationSample(
                sample: $0.sample,
                regions: replacement[$0.sample.id] ?? $0.regions,
            )
        }
        let resulting = DayAggregator(calendar: calendar, timeZone: calendar.timeZone)
            .report(for: day.year, history: corrected, manualDays: manuals)
            .days.first { $0.day == day }?.regions ?? []

        if !edits.isEmpty {
            let proposal = SampleCorrectionProposal(
                reviewID: reviewID,
                day: presence,
                resultingRegions: resulting,
                edits: edits,
                dataGenerationID: reads.dataGenerationID,
                evidence: .init(
                    history: context,
                    manualDays: manuals,
                    primaryRegions: primaryRegions,
                    trackedRegions: attributor.loadedRegions,
                    driftThresholdMeters: driftThresholdMeters,
                    calendar: calendar,
                    flights: dayFlights,
                ),
            )
            return GPSCorrectionReview(
                id: reviewID,
                day: presence,
                points: points,
                state: .ready(proposal, flight: dayFlights.last),
                flights: dayFlights,
            )
        }
        guard let flight = dayFlights.last else { return nil }
        return GPSCorrectionReview(
            id: reviewID,
            day: presence,
            points: points,
            state: .completed(flight),
            flights: dayFlights,
        )
    }

    private func boundaryReplacement(
        for entry: AttributedLocationSample,
        neighbors: [AttributedLocationSample],
        airborne: Set<UUID>,
        primaryRegions: [Region],
        threshold: Double,
    ) -> Region? {
        let sample = entry.sample
        guard entry.regions.contains(.other),
              usable(sample),
              attributor.region(at: sample.coordinate) == .other,
              !airborne.contains(sample.id) else { return nil }
        let beforeIndex = insertionIndex(
            in: neighbors,
            at: sample.timestamp.addingTimeInterval(-1),
            afterEqual: true,
        ) - 1
        let afterIndex = insertionIndex(
            in: neighbors,
            at: sample.timestamp.addingTimeInterval(1),
            afterEqual: false,
        )
        guard beforeIndex >= 0, afterIndex < neighbors.count else { return nil }
        let before = neighbors[beforeIndex]
        let after = neighbors[afterIndex]
        guard sample.timestamp.timeIntervalSince(before.sample.timestamp) <= 10 * 60,
              after.sample.timestamp.timeIntervalSince(sample.timestamp) <= 10 * 60,
              !airborne.contains(before.sample.id), !airborne.contains(after.sample.id),
              localMovement(before.sample, sample),
              localMovement(sample, after.sample) else { return nil }
        let region = attributor.region(at: before.sample.coordinate)
        guard region != .other,
              primaryRegions.contains(region),
              before.regions.contains(region), after.regions.contains(region),
              attributor.region(at: after.sample.coordinate) == region,
              let distance = attributor.distanceToBoundary(of: region, from: sample.coordinate),
              distance.isFinite, distance <= threshold else { return nil }
        return region
    }

    /// Binary search keeps dense boundary recordings from rescanning the day
    /// for every proposed sample.
    private func insertionIndex(
        in samples: [AttributedLocationSample],
        at timestamp: Date,
        afterEqual: Bool,
    ) -> Int {
        var lower = 0
        var upper = samples.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            let date = samples[middle].sample.timestamp
            if date < timestamp || (afterEqual && date == timestamp) {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func localMovement(_ before: LocationSample, _ after: LocationSample) -> Bool {
        let seconds = after.timestamp.timeIntervalSince(before.timestamp)
        guard seconds > 0 else { return false }
        let upperDistance = before.coordinate.distance(to: after.coordinate)
            + before.horizontalAccuracy + after.horizontalAccuracy
        return upperDistance / seconds * 3.6 < 150
    }

    private func usable(_ sample: LocationSample) -> Bool {
        sample.timestamp.timeIntervalSince1970.isFinite
            && sample.coordinate.latitude.isFinite && sample.coordinate.longitude.isFinite
            && (-90 ... 90).contains(sample.coordinate.latitude)
            && (-180 ... 180).contains(sample.coordinate.longitude)
            && sample.horizontalAccuracy.isFinite && (0 ... 250).contains(sample.horizontalAccuracy)
    }
}
