import Foundation

/// Conservative jet-flight inference over independent device trajectories. All
/// thresholds are product policy, not measurements of a particular user's trip.
/// Short-interval fixes retain their identities but do not break motion baselines.
public struct FlightTrajectoryAnalyzer: Sendable {
    private typealias Policy = GPSCorrectionPolicy.Trajectory

    private struct Leg {
        let seconds: TimeInterval
        let distance: Double
        let lowerSpeed: Double
        let upperSpeed: Double

        var isCore: Bool {
            // Every cruise leg must clear the minimum after subtracting positional
            // uncertainty. Averaging the run could hide a slow or contradictory leg.
            qualifies(minimumSpeed: Policy.minimumCruiseSpeedKMH)
        }

        var isTransition: Bool {
            qualifies(minimumSpeed: Policy.minimumTransitionSpeedKMH)
        }

        private func qualifies(minimumSpeed: Double) -> Bool {
            seconds >= Policy.minimumAnchorInterval
                && seconds <= Policy.maximumLegInterval
                && lowerSpeed >= minimumSpeed
                && upperSpeed <= Policy.maximumPlausibleSpeedKMH
        }
    }

    /// An anchor offset, including the exclusive end of the trajectory.
    private struct AnchorIndex {
        let offset: Int
    }

    private struct Core {
        let start: Int
        let end: Int
    }

    private struct Ground {
        let start: Int
        let confirmation: Int
    }

    public init() {}

    public func analyze(samples: [LocationSample], now: Date) -> [FlightAssessment] {
        // A device change cannot manufacture travel or land another device's flight.
        // Legacy observations form a separate track; asserted locations are not motion evidence.
        let tracks = Dictionary(grouping: samples.filter(\.source.isGPS), by: \.recordingDeviceID)
        return tracks.flatMap { deviceID, samples in
            analyzeTrack(samples, deviceID: deviceID, now: now)
        }.sorted {
            if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
            return $0.id.departureSampleID.uuidString < $1.id.departureSampleID.uuidString
        }
    }

    private func analyzeTrack(
        _ samples: [LocationSample],
        deviceID: RecordingDeviceID?,
        now: Date,
    ) -> [FlightAssessment] {
        let usable = samples.filter { Self.isUsable($0) && $0.timestamp <= now }.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            if $0.horizontalAccuracy != $1.horizontalAccuracy {
                return $0.horizontalAccuracy < $1.horizontalAccuracy
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        // Build motion baselines from independent fixes. Retain denser usable callbacks
        // so they can veto ground dwell and keep their own correction identities.
        var anchors: [LocationSample] = []
        for sample in usable {
            if let last = anchors.last,
               sample.timestamp.timeIntervalSince(last.timestamp)
               < Policy.minimumAnchorInterval
            { continue }
            anchors.append(sample)
        }
        guard anchors.count >= 3 else { return [] }
        // Each leg connects anchor i to i + 1. Cores require sustained, directed
        // progress; isolated jumps, reversals, and implausible speeds remain unknown.
        let legs = zip(anchors, anchors.dropFirst()).map { Self.leg(from: $0, to: $1) }
        let cores = Self.cores(anchors: anchors, legs: legs)
        guard !cores.isEmpty else { return [] }
        let grounds = Self.grounds(anchors: anchors, legs: legs, observations: usable)
        // Nearby cruise cores share a review until observed ground dwell separates
        // them. Unsupported gaps inside a review still do not become airborne evidence.
        var groups: [[Core]] = []
        for core in cores {
            if let previous = groups.last?.last,
               anchors[core.start].timestamp.timeIntervalSince(anchors[previous.end].timestamp)
               <= Policy.maximumLegInterval,
               !grounds.contains(where: {
                   $0.start >= previous.end && $0.confirmation <= core.start
               })
            {
                groups[groups.count - 1].append(core)
            } else {
                groups.append([core])
            }
        }
        return groups.indices.compactMap { index in
            assessment(
                cores: groups[index],
                anchors: anchors,
                legs: legs,
                usable: usable,
                grounds: grounds,
                nextStart: index + 1 < groups.count ? Self.transitionStart(
                    for: groups[index + 1][0],
                    anchors: anchors,
                    legs: legs,
                ) : AnchorIndex(offset: anchors.endIndex),
                deviceID: deviceID,
                now: now,
            )
        }
    }

    private func assessment(
        cores: [Core],
        anchors: [LocationSample],
        legs: [Leg],
        usable: [LocationSample],
        grounds: [Ground],
        nextStart: AnchorIndex,
        deviceID: RecordingDeviceID?,
        now: Date,
    ) -> FlightAssessment? {
        // zip creates anchors.count - 1 legs; cores and grounds only emit anchor
        // indices reached through those legs. Grouping preserves core order, and
        // the next group's transition starts after this group's last core. Check
        // that correspondence here before any private array index is used.
        guard let first = cores.first,
              let last = cores.last,
              anchors.count >= 3,
              legs.count == anchors.count - 1,
              cores.allSatisfy({
                  anchors.indices.contains($0.start) && anchors.indices.contains($0.end)
                      && $0.end - $0.start >= 2
              }),
              zip(cores, cores.dropFirst()).allSatisfy({ $0.end <= $1.start }),
              nextStart.offset >= last.end, nextStart.offset <= anchors.count,
              grounds.allSatisfy({
                  anchors.indices.contains($0.start) && anchors.indices.contains($0.confirmation)
                      && $0.confirmation - $0.start >= 2
              })
        else {
            assertionFailure(
                "Flight assessment requires ordered cores and matching anchor/leg indices",
            )
            return nil
        }
        let arrival = grounds.first { $0.start >= last.end && $0.confirmation <= nextStart.offset }
        let departure = grounds.last { $0.confirmation <= first.start }
        // Extend each cruise core only through bounded, plausible takeoff/approach
        // legs. Arrival and the next departure bound ownership of these observations.
        var supportedLegs: Set<Int> = []
        for core in cores {
            let before = Self.transitionStart(for: core, anchors: anchors, legs: legs)
            supportedLegs.formUnion(before.offset ..< core.end)
            var after = core.end
            let limit = arrival?.start ?? nextStart.offset - 1
            while after < limit,
                  legs[after].isTransition,
                  anchors[after + 1].timestamp.timeIntervalSince(anchors[core.end].timestamp)
                  <= Policy.maximumTransitionDuration
            {
                supportedLegs.insert(after)
                after += 1
            }
        }
        // Confirmed endpoint dwell protects ground identities before selecting any
        // airborne points, including dense callbacks between the independent anchors.
        let groundIDs = Set([departure, arrival].compactMap(\.self).flatMap { ground in
            usable.filter {
                $0.timestamp >= anchors[ground.start].timestamp
                    && $0.timestamp <= anchors[ground.confirmation].timestamp
                    && Self.fitsGround($0, origin: anchors[ground.start])
            }.map(\.id)
        })
        // Every accepted core supplies at least two legs. Absence is a broken
        // inference invariant, never a measured speed of zero.
        guard let startIndex = supportedLegs.min(),
              let lastLegIndex = supportedLegs.max(),
              let peakSpeedKMH = supportedLegs.map({
                  GPSCorrectionPolicy.kilometersPerHour(
                      fromMetersPerSecond: legs[$0].distance / legs[$0].seconds,
                  )
              }).max()
        else {
            assertionFailure("A flight requires supported motion legs")
            return nil
        }
        let endIndex = lastLegIndex + 1
        let earliest = anchors[startIndex]
        let latest = anchors[endIndex]
        var airborneIDs: Set<UUID> = []
        var sampleIndex = 0
        for legIndex in supportedLegs.sorted() {
            let before = anchors[legIndex]
            let after = anchors[legIndex + 1]
            // A gap leaves both neighboring endpoints unknown, even when the
            // cruise cores on either side belong to one flight review.
            let startsRun = !supportedLegs.contains(legIndex - 1)
            let endsRun = !supportedLegs.contains(legIndex + 1)
            while sampleIndex < usable.count, usable[sampleIndex].timestamp < before.timestamp {
                sampleIndex += 1
            }
            var candidate = sampleIndex
            while candidate < usable.count, usable[candidate].timestamp <= after.timestamp {
                let sample = usable[candidate]
                if !startsRun || (sample.timestamp > before.timestamp
                    && !Self.isSameObservation(sample, as: before)),
                    !endsRun || (sample.timestamp < after.timestamp
                        && !Self.isSameObservation(sample, as: after)),
                    !groundIDs.contains(sample.id),
                    Self.fitsMotion(sample, from: before, to: after)
                {
                    airborneIDs.insert(sample.id)
                }
                candidate += 1
            }
        }
        var inferredEndpoints: [FlightEndpointInference] = []
        for core in cores where !supportedLegs.contains(core.start - 1) {
            let endpoint = anchors[core.start]
            let observations = usable.filter { Self.isSameObservation($0, as: endpoint) }
            guard observations.allSatisfy({ !groundIDs.contains($0.id) }),
                  let reason = FlightEndpointInference.reason(
                      cruise: Array(anchors[core.start ... core.end]),
                      previous: core.start > 0 ? anchors[core.start - 1] : nil,
                      endpointObservations: observations,
                  ) else { continue }
            for sample in observations where Self.fitsMotion(
                sample,
                from: endpoint,
                to: anchors[core.start + 1],
            ) {
                airborneIDs.insert(sample.id)
                inferredEndpoints.append(.init(sampleID: sample.id, reason: reason))
            }
        }
        let observationLimit = if let arrival {
            anchors[arrival.confirmation].timestamp
        } else if nextStart.offset < anchors.count {
            anchors[nextStart.offset].timestamp
        } else {
            now
        }
        // A later flight owns its first observation, including its supported
        // takeoff transition. It cannot extend an older unresolved review.
        let lastObservation = usable.last {
            $0.timestamp <= observationLimit
                && (arrival != nil || nextStart.offset == anchors.count
                    || $0.timestamp < anchors[nextStart.offset].timestamp)
        } ?? latest
        let trailingMotionIsPlausible = anchors.last(where: {
            $0.timestamp <= lastObservation.timestamp
        }).map { Self.isPlausible(lastObservation, relativeTo: $0) } ?? false
        let observationStillCruising = trailingMotionIsPlausible
            && (anchors.last(where: {
                lastObservation.timestamp.timeIntervalSince($0.timestamp) >= Policy
                    .minimumAnchorInterval
            }).map { Self.leg(from: $0, to: lastObservation).isCore } ?? false)
        let lastFlightAt = observationStillCruising
            ? max(latest.timestamp, lastObservation.timestamp) : latest.timestamp
        // Arrival wins immediately when the observed dwell confirms it. Freshness
        // only changes the live-flight label when arrival evidence is still missing.
        let progress: FlightAssessment.Progress = if let arrival {
            .completed(arrivedAt: anchors[arrival.start].timestamp)
        } else if observationStillCruising,
                  now.timeIntervalSince(lastFlightAt) < GPSCorrectionPolicy.Presentation
                  .liveFlightFreshnessInterval
        {
            .flightLikely
        } else {
            .awaitingArrival
        }
        return FlightAssessment(
            id: .init(
                recordingSource: deviceID.map(FlightAssessment.RecordingSource.device) ?? .legacy,
                departureSampleID: earliest.id,
            ),
            startedAt: earliest.timestamp,
            lastObservationAt: lastObservation.timestamp,
            lastFlightAt: lastFlightAt,
            airborneSampleIDs: airborneIDs,
            groundSampleIDs: groundIDs,
            peakSpeedKMH: peakSpeedKMH,
            progress: progress,
            inferredEndpoints: inferredEndpoints,
        )
    }

    private static func transitionStart(
        for core: Core,
        anchors: [LocationSample],
        legs: [Leg],
    ) -> AnchorIndex {
        var start = core.start
        while start > 0,
              legs[start - 1].isTransition,
              anchors[core.start].timestamp.timeIntervalSince(anchors[start - 1].timestamp)
              <= Policy.maximumTransitionDuration
        {
            start -= 1
        }
        return AnchorIndex(offset: start)
    }

    private static func cores(anchors: [LocationSample], legs: [Leg]) -> [Core] {
        var result: [Core] = []
        var index = 0
        while index < legs.count {
            guard legs[index].isCore else { index += 1; continue }
            let start = index
            var path = 0.0
            while index < legs.count, legs[index].isCore {
                path += legs[index].distance
                index += 1
            }
            let seconds = anchors[index].timestamp.timeIntervalSince(anchors[start].timestamp)
            let progress = anchors[start].coordinate.distance(to: anchors[index].coordinate)
            // Two legs provide three anchors. Require duration and net displacement
            // as well as per-leg speed so a short burst or out-and-back jump cannot qualify.
            if index - start >= 2, seconds >= Policy.minimumCruiseDuration,
               path > 0,
               progress / path >= Policy.minimumDirectProgressRatio
            {
                result.append(Core(start: start, end: index))
            }
        }
        return result
    }

    private static func grounds(
        anchors: [LocationSample],
        legs: [Leg],
        observations: [LocationSample],
    ) -> [Ground] {
        // Preserve dense contradictory callbacks as evidence. Bucketing once
        // keeps each bounded ground-window check local to its own observations.
        var observationsByLeg = [[LocationSample]](repeating: [], count: legs.count)
        var legIndex = 0
        for sample in observations {
            while legIndex + 1 < legs.count, sample.timestamp > anchors[legIndex + 1].timestamp {
                legIndex += 1
            }
            if sample.timestamp <= anchors[legIndex + 1].timestamp {
                observationsByLeg[legIndex].append(sample)
                if legIndex + 1 < legs.count,
                   sample.timestamp == anchors[legIndex + 1].timestamp
                {
                    observationsByLeg[legIndex + 1].append(sample)
                }
            }
        }
        // Confirm arrival from at least three compatible anchors spanning the dwell
        // minimum. The window and gap caps prevent silence from filling missing evidence;
        // all intervening callbacks must fit the same ground cluster.
        var result: [Ground] = []
        for start in anchors.indices where fitsGround(anchors[start], origin: anchors[start]) {
            var end = start + 1
            while end < anchors.count,
                  anchors[end].timestamp.timeIntervalSince(anchors[start].timestamp)
                  <= Policy.maximumGroundWindow,
                  legs[end - 1].seconds <= Policy.maximumGroundGap,
                  legs[end - 1].upperSpeed <= Policy.maximumGroundSpeedKMH,
                  fitsGround(anchors[end], origin: anchors[start]),
                  observationsByLeg[end - 1].allSatisfy({
                      fitsGround($0, origin: anchors[start])
                  })
            {
                if end - start >= 2,
                   anchors[end].timestamp.timeIntervalSince(anchors[start].timestamp)
                   >= Policy.minimumGroundDuration
                {
                    result.append(Ground(start: start, confirmation: end))
                    break
                }
                end += 1
            }
        }
        return result
    }

    private static func isSameObservation(
        _ sample: LocationSample,
        as endpoint: LocationSample,
    ) -> Bool {
        abs(sample.timestamp.timeIntervalSince(endpoint.timestamp))
            < Policy.sameObservationInterval
            && sample.coordinate.distance(to: endpoint.coordinate)
            <= sample.horizontalAccuracy + endpoint.horizontalAccuracy
    }

    private static func fitsGround(_ sample: LocationSample, origin: LocationSample) -> Bool {
        if let speed = sample.motion?.speed,
           GPSCorrectionPolicy.kilometersPerHour(
               fromMetersPerSecond: speed.metersPerSecond + speed.accuracyMetersPerSecond,
           ) > Policy.maximumGroundSpeedKMH
        { return false }
        return sample.coordinate.distance(to: origin.coordinate)
            + sample.horizontalAccuracy + origin.horizontalAccuracy <= Policy
            .groundRadiusMeters
    }

    private static func fitsMotion(
        _ sample: LocationSample,
        from before: LocationSample,
        to after: LocationSample,
    ) -> Bool {
        isPlausible(sample, relativeTo: before) && isPlausible(sample, relativeTo: after)
    }

    private static func isPlausible(
        _ sample: LocationSample,
        relativeTo endpoint: LocationSample,
    ) -> Bool {
        let seconds = abs(sample.timestamp.timeIntervalSince(endpoint.timestamp))
        let distance = sample.coordinate.distance(to: endpoint.coordinate)
        let uncertainty = sample.horizontalAccuracy + endpoint.horizontalAccuracy
        if seconds < Policy.sameObservationInterval {
            return distance <= uncertainty
        }
        return GPSCorrectionPolicy.kilometersPerHour(
            fromMetersPerSecond: max(0, distance - uncertainty) / seconds,
        ) <= Policy.maximumPlausibleSpeedKMH
    }

    private static func leg(from before: LocationSample, to after: LocationSample) -> Leg {
        let seconds = after.timestamp.timeIntervalSince(before.timestamp)
        let distance = before.coordinate.distance(to: after.coordinate)
        let uncertainty = before.horizontalAccuracy + after.horizontalAccuracy
        return Leg(
            seconds: seconds,
            distance: distance,
            lowerSpeed: GPSCorrectionPolicy.kilometersPerHour(
                fromMetersPerSecond: max(0, distance - uncertainty) / seconds,
            ),
            upperSpeed: GPSCorrectionPolicy.kilometersPerHour(
                fromMetersPerSecond: (distance + uncertainty) / seconds,
            ),
        )
    }

    private static func isUsable(_ sample: LocationSample) -> Bool {
        sample.timestamp.timeIntervalSince1970.isFinite
            && sample.coordinate.latitude.isFinite && sample.coordinate.longitude.isFinite
            && (-90 ... 90).contains(sample.coordinate.latitude)
            && (-180 ... 180).contains(sample.coordinate.longitude)
            && sample.horizontalAccuracy.isFinite
            && (0 ... GPSCorrectionPolicy.maximumHorizontalAccuracyMeters)
            .contains(sample.horizontalAccuracy)
    }
}
