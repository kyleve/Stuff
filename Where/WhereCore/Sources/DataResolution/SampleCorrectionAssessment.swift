import Foundation
import RegionKit

/// Combines trajectory and local boundary evidence into exact, reversible GPS
/// edits. Unknown observations and user assertions always retain their support.
struct SampleCorrectionAssessment {
    private typealias BoundaryPolicy = GPSCorrectionPolicy.Boundary

    let attributor: any RegionAttributing
    let calendar: Calendar

    func reviews(
        reads: DataIssueReads,
        primaryRegions: [Region],
        driftThresholdMeters: Double,
        now: Date,
    ) -> [GPSCorrectionReview] {
        // Infer flights from raw observations across midnight. Existing corrections
        // must not erase the evidence that explains why those samples were edited.
        let flights = FlightTrajectoryAnalyzer().analyze(
            samples: reads.history.rawSamples,
            now: now,
        )
        // Bucket effective attribution only after trajectory analysis. This keeps
        // flight inference independent of the calendar used to show the review.
        let byDay = Dictionary(grouping: reads.history.samples) {
            CalendarDay(from: $0.sample.timestamp, in: calendar)
        }
        // Revisions follow a sample identity across days. A conflict anywhere
        // in the reviewed snapshot must prevent correcting that identity.
        let conflictingSampleIDs = Set(Dictionary(
            grouping: reads.history.samples,
            by: \.sample.id,
        ).filter { Set($0.value).count > 1 }.keys)
        let revisionsBySample = Dictionary(grouping: reads.history.revisions, by: \.sampleID)
        let allAirborne = flights
            .reduce(into: Set<LocationSample.ID>()) { $0.formUnion($1.airborneSampleIDs) }
        // Produce one review per report day. Adjacent-day observations provide
        // corroborating neighbors without adding edits outside that reviewed day.
        return byDay.keys.filter { $0.year == reads.report.year }.sorted().compactMap { day in
            let start = day.startOfDay(in: calendar)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
                assertionFailure("Cannot derive a calendar day's successor")
                return nil
            }
            let contextStart = start
                .addingTimeInterval(-GPSCorrectionPolicy.Review.contextPaddingInterval)
            let contextEnd = end
                .addingTimeInterval(GPSCorrectionPolicy.Review.contextPaddingInterval)
            let contextDays = CalendarDay(from: contextStart, in: calendar)
                .days(through: CalendarDay(from: contextEnd, in: calendar))
            let context = contextDays.flatMap { byDay[$0] ?? [] }.filter {
                $0.sample.timestamp >= contextStart && $0.sample.timestamp < contextEnd
            }.sorted { $0.sample.timestamp < $1.sample.timestamp }
            return review(
                day: day,
                entries: byDay[day] ?? [],
                conflictingSampleIDs: conflictingSampleIDs,
                allAirborne: allAirborne,
                flights: flights,
                reads: reads,
                primaryRegions: primaryRegions,
                driftThresholdMeters: driftThresholdMeters,
                context: LocationHistoryProjection(
                    samples: context,
                    revisions: context.flatMap { revisionsBySample[$0.sample.id] ?? [] }
                        .sorted { $0.id < $1.id },
                ),
            )
        }
    }

    private func review(
        day: CalendarDay,
        entries: [AttributedLocationSample],
        conflictingSampleIDs: Set<LocationSample.ID>,
        allAirborne: Set<LocationSample.ID>,
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
        // Keep every flight intersecting the local day, including an unfinished
        // flight whose last observation extends beyond its last supported leg.
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
        let kind: SampleCorrectionProposal.Kind = dayFlights.isEmpty ? .borderDrift : .flight
        let reviewID = kind.reviewID(for: day)
        // Arrival authorizes only that flight's edits. Another unfinished flight
        // on the same day must retain its evidence without blocking completed trips.
        let pending = dayFlights.last(where: \.isPending)
        let completedFlights = dayFlights.filter { !$0.isPending }

        // Boundary corroboration stays on one recording device. Samples from a
        // second device cannot establish where this device was before or after.
        let boundaryEvidence = Dictionary(grouping: context.samples.filter {
            $0.sample.source.isGPS && usable($0.sample)
        }, by: \.sample.recordingDeviceID)
        // Edit only airborne samples from this day's completed flights. Exclude
        // all flights from boundary corroboration, including flights on nearby days.
        let airborne = completedFlights.reduce(into: Set<LocationSample.ID>()) {
            $0.formUnion($1.airborneSampleIDs)
        }
        let manuals = reads.manualDays.filter { $0.day == day }
        struct Candidate {
            let timestamp: Date
            let edit: SampleCorrectionProposal.Edit
        }
        var candidates: [Candidate] = []
        // An explicit whole-day assertion is authoritative. Keep it intact and
        // keep the flight information beneath it.
        if !manuals.contains(where: \.isAuthoritative) {
            // Concurrent imports can sync multiple physical rows for one sample.
            // Review its identity once, retaining conflicting representations as
            // unknown evidence instead of choosing an arbitrary row to correct.
            for duplicates in Dictionary(grouping: entries, by: \.sample.id).values {
                guard let entry = duplicates.first,
                      !conflictingSampleIDs.contains(entry.sample.id),
                      entry.sample.source.isGPS, !entry.regions.isEmpty else { continue }
                if airborne.contains(entry.sample.id) {
                    // Empty attribution removes presence from an airborne GPS sample.
                    // Raw coordinates and timestamps remain available for future review.
                    candidates.append(Candidate(
                        timestamp: entry.sample.timestamp,
                        edit: .init(sampleID: entry.sample.id, replacementRegions: []),
                    ))
                } else if pending == nil, let region = boundaryReplacement(
                    for: entry,
                    neighbors: boundaryEvidence[entry.sample.recordingDeviceID] ?? [],
                    airborne: allAirborne,
                    primaryRegions: primaryRegions,
                    threshold: driftThresholdMeters,
                ), entry.regions != [region] {
                    candidates.append(Candidate(
                        timestamp: entry.sample.timestamp,
                        edit: .init(sampleID: entry.sample.id, replacementRegions: [region]),
                    ))
                }
            }
        }
        // Present edits chronologically. UUID breaks simultaneous-observation ties
        // so CloudKit row delivery order cannot change a reviewed proposal.
        let edits = candidates.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return $0.edit.sampleID < $1.edit.sampleID
        }.map(\.edit)
        let replacement = Dictionary(uniqueKeysWithValues: edits.map { (
            $0.sampleID,
            $0.replacementRegions,
        ) })
        // Compute the displayed result through the ordinary day aggregator so
        // manual assertions retain the same precedence as the eventual Apply.
        let corrected = entries.map {
            AttributedLocationSample(
                sample: $0.sample,
                regions: replacement[$0.sample.id] ?? $0.regions,
            )
        }
        let resulting = DayAggregator(calendar: calendar, timeZone: calendar.timeZone)
            .report(for: day.year, history: corrected, manualDays: manuals)
            .days.first { $0.day == day }?.regions ?? []

        // Capture all decision inputs with the proposal. Apply must reassess them
        // inside its store transaction before writing these exact sample edits.
        if !edits.isEmpty {
            let proposal = SampleCorrectionProposal(
                kind: kind,
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
                state: .ready(proposal, flight: completedFlights.last),
                flights: dayFlights,
            )
        }
        // With no completed-flight edits left, keep unfinished trips reviewable.
        // Boundary cleanup still waits while any flight on this day is unresolved.
        if let pending {
            return GPSCorrectionReview(
                id: reviewID,
                day: presence,
                points: points,
                state: .pending(pending),
                flights: dayFlights,
            )
        }
        // A landed flight without GPS edits remains an informational review.
        // A day without flight evidence or edits needs no review.
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
        airborne: Set<LocationSample.ID>,
        primaryRegions: [Region],
        threshold: Double,
    ) -> Region? {
        let sample = entry.sample
        // Correct only an unresolved coordinate outside the tracked polygons.
        // Valid regional attribution and supported airborne observations remain intact.
        guard entry.regions.contains(.other),
              usable(sample),
              attributor.region(at: sample.coordinate) == .other,
              !airborne.contains(sample.id) else { return nil }
        // Find the closest independent observations on each side. Near-simultaneous
        // callbacks cannot count as separate evidence of a stable local visit.
        let beforeIndex = insertionIndex(
            in: neighbors,
            at: sample.timestamp.addingTimeInterval(-BoundaryPolicy.neighborExclusionInterval),
            afterEqual: true,
        ) - 1
        let afterIndex = insertionIndex(
            in: neighbors,
            at: sample.timestamp.addingTimeInterval(BoundaryPolicy.neighborExclusionInterval),
            afterEqual: false,
        )
        guard beforeIndex >= 0, afterIndex < neighbors.count else { return nil }
        let before = neighbors[beforeIndex]
        let after = neighbors[afterIndex]
        // Ten minutes bounds each side of the visit. Longer gaps or fast motion
        // can hide genuine travel, so those samples must remain uncorrected.
        guard sample.timestamp.timeIntervalSince(before.sample.timestamp)
            <= BoundaryPolicy.maximumNeighborInterval,
            after.sample.timestamp.timeIntervalSince(sample.timestamp)
            <= BoundaryPolicy.maximumNeighborInterval,
            !airborne.contains(before.sample.id), !airborne.contains(after.sample.id),
            localMovement(before.sample, sample),
            localMovement(sample, after.sample) else { return nil }
        // Both raw coordinates and effective attribution must support the same
        // primary region. The user's drift threshold is the final distance limit.
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
        // Use the upper distance bound, including both accuracy circles. Boundary
        // cleanup requires local movement even under the least favorable GPS error.
        let upperDistance = before.coordinate.distance(to: after.coordinate)
            + before.horizontalAccuracy + after.horizontalAccuracy
        return GPSCorrectionPolicy.kilometersPerHour(fromMetersPerSecond: upperDistance / seconds)
            < BoundaryPolicy.maximumLocalSpeedKMH
    }

    private func usable(_ sample: LocationSample) -> Bool {
        sample.timestamp.timeIntervalSince1970.isFinite
            && sample.coordinate.latitude.isFinite && sample.coordinate.longitude.isFinite
            && (-90 ... 90).contains(sample.coordinate.latitude)
            && (-180 ... 180).contains(sample.coordinate.longitude)
            && sample.horizontalAccuracy.isFinite
            && (0 ... GPSCorrectionPolicy.maximumHorizontalAccuracyMeters)
            .contains(sample.horizontalAccuracy)
    }
}
