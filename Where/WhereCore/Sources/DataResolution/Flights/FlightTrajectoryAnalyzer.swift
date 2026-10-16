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

    /// Confirmed ground dwell can share the next departure anchor. Pending
    /// observations stop earlier when that trip owns a corroborating fix.
    private struct NextFlightBoundary {
        let arrivalConfirmationLimit: AnchorIndex
        let observationStart: AnchorIndex
    }

    private enum Segment {
        case cruise(Range<Int>)
        case displacement(Int)

        var start: Int {
            switch self {
                case let .cruise(legs): legs.lowerBound
                case let .displacement(leg): leg
            }
        }

        var end: Int {
            switch self {
                case let .cruise(legs): legs.upperBound
                case let .displacement(leg): leg + 1
            }
        }

        var isCruise: Bool {
            switch self {
                case .cruise: true
                case .displacement: false
            }
        }
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
        let cruise = Self.cruiseSegments(anchors: anchors, legs: legs)
        // Sparse displacement can establish a trip without supplying observed cruise
        // legs. Merge both evidence kinds before arrival and trip ownership are resolved.
        let displacement = (1 ..< anchors.count - 2).compactMap { start -> Segment? in
            guard !cruise.contains(where: { $0.start <= start && $0.end > start }),
                  FlightDisplacementInference.supportsFlight(
                      from: anchors[start],
                      to: anchors[start + 1],
                      previous: anchors[start - 1],
                      next: anchors[start + 2],
                      observations: usable,
                  ) else { return nil }
            return .displacement(start)
        }
        let segments = (cruise + displacement).sorted { $0.start < $1.start }
        guard !segments.isEmpty else { return [] }
        let grounds = Self.grounds(anchors: anchors, legs: legs, observations: usable)
        // Nearby cruise segments share a review until observed ground dwell separates
        // them. Unsupported gaps inside a review still do not become airborne evidence.
        var groups: [[Segment]] = []
        for segment in segments {
            if let previous = groups.last?.last,
               anchors[segment.start].timestamp.timeIntervalSince(anchors[previous.end].timestamp)
               <= Policy.maximumLegInterval,
               !grounds.contains(where: {
                   $0.start >= previous.end && $0.confirmation <= segment.start
               })
            {
                groups[groups.count - 1].append(segment)
            } else {
                groups.append([segment])
            }
        }
        return groups.indices.compactMap { index in
            let next: NextFlightBoundary
            if index + 1 < groups.count {
                let segment = groups[index + 1][0]
                let observationStart = Self.observationStart(
                    for: segment,
                    anchors: anchors,
                    legs: legs,
                )
                next = NextFlightBoundary(
                    arrivalConfirmationLimit: segment.isCruise
                        ? observationStart : AnchorIndex(offset: segment.start),
                    observationStart: observationStart,
                )
            } else {
                let end = AnchorIndex(offset: anchors.endIndex)
                next = NextFlightBoundary(arrivalConfirmationLimit: end, observationStart: end)
            }
            return assessment(
                segments: groups[index],
                anchors: anchors,
                legs: legs,
                usable: usable,
                grounds: grounds,
                next: next,
                deviceID: deviceID,
                now: now,
            )
        }
    }

    private func assessment(
        segments: [Segment],
        anchors: [LocationSample],
        legs: [Leg],
        usable: [LocationSample],
        grounds: [Ground],
        next: NextFlightBoundary,
        deviceID: RecordingDeviceID?,
        now: Date,
    ) -> FlightAssessment? {
        // zip creates anchors.count - 1 legs; segments and grounds only emit anchor
        // indices reached through those legs. Grouping preserves segment order, and
        // the next group's transition starts after this group's last segment. Check
        // that correspondence here before any private array index is used.
        guard let first = segments.first,
              let last = segments.last,
              anchors.count >= 3,
              legs.count == anchors.count - 1,
              segments.allSatisfy({
                  anchors.indices.contains($0.start) && anchors.indices.contains($0.end)
                      && $0.end - $0.start >= ($0.isCruise ? 2 : 1)
              }),
              zip(segments, segments.dropFirst()).allSatisfy({ $0.end <= $1.start }),
              next.observationStart.offset >= last.end,
              next.arrivalConfirmationLimit.offset >= next.observationStart.offset,
              next.arrivalConfirmationLimit.offset <= anchors.count,
              grounds.allSatisfy({
                  anchors.indices.contains($0.start) && anchors.indices.contains($0.confirmation)
                      && $0.confirmation - $0.start >= 2
              })
        else {
            assertionFailure(
                "Flight assessment requires ordered segments and matching anchor/leg indices",
            )
            return nil
        }
        let arrival = grounds.first {
            $0.start >= last.end && $0.confirmation <= next.arrivalConfirmationLimit.offset
        }
        let departure = grounds.last { $0.confirmation <= first.start }
        // Extend each cruise segment only through bounded, plausible takeoff/approach
        // legs. Arrival and the next departure bound ownership of these observations.
        var supportedLegs: Set<Int> = []
        for segment in segments where segment.isCruise {
            let before = Self.observationStart(for: segment, anchors: anchors, legs: legs)
            supportedLegs.formUnion(before.offset ..< segment.end)
            var after = segment.end
            let limit = arrival?.start ?? next.observationStart.offset - 1
            while after < limit,
                  legs[after].isTransition,
                  anchors[after + 1].timestamp.timeIntervalSince(anchors[segment.end].timestamp)
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
        // Displacement contributes a trip interval and average speed, but never
        // enters supportedLegs or the automatic airborne-point correction set.
        let startIndex = min(first.start, supportedLegs.min() ?? first.start)
        let endIndex = max(last.end, supportedLegs.max().map { $0 + 1 } ?? last.end)
        let travelLegs = supportedLegs
            .union(segments.filter { !$0.isCruise }.map(\.start))
        guard let peakSpeedKMH = travelLegs.map({
            GPSCorrectionPolicy.kilometersPerHour(
                fromMetersPerSecond: legs[$0].distance / legs[$0].seconds,
            )
        }).max() else {
            assertionFailure("A flight requires observed motion or corroborated displacement")
            return nil
        }
        let earliest = anchors[startIndex]
        let latest = anchors[endIndex]
        var airborneIDs: Set<UUID> = []
        var sampleIndex = 0
        for legIndex in supportedLegs.sorted() {
            let before = anchors[legIndex]
            let after = anchors[legIndex + 1]
            // A gap alone leaves both neighboring endpoints unknown. Separate
            // corroboration below can support the first resumed observation.
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
        for segment in segments
            where segment.isCruise && !supportedLegs.contains(segment.start - 1)
        {
            let endpoint = anchors[segment.start]
            let observations = usable.filter { Self.isSameObservation($0, as: endpoint) }
            guard observations.allSatisfy({ !groundIDs.contains($0.id) }),
                  let reason = FlightEndpointInference.reason(
                      cruise: Array(anchors[segment.start ... segment.end]),
                      previous: segment.start > 0 ? anchors[segment.start - 1] : nil,
                      endpointObservations: observations,
                  ) else { continue }
            for sample in observations where Self.fitsMotion(
                sample,
                from: endpoint,
                to: anchors[segment.start + 1],
            ) {
                if airborneIDs.insert(sample.id).inserted {
                    inferredEndpoints.append(.init(sampleID: sample.id, reason: reason))
                }
            }
        }
        let observationLimit = if let arrival {
            anchors[arrival.confirmation].timestamp
        } else if next.observationStart.offset < anchors.count {
            anchors[next.observationStart.offset].timestamp
        } else {
            now
        }
        // A later flight owns its first observation, including its supported
        // takeoff transition. It cannot extend an older unresolved review.
        let lastObservation = usable.last {
            $0.timestamp <= observationLimit
                && (arrival != nil || next.observationStart.offset == anchors.count
                    || $0.timestamp < anchors[next.observationStart.offset].timestamp)
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

    private static func observationStart(
        for segment: Segment,
        anchors: [LocationSample],
        legs: [Leg],
    ) -> AnchorIndex {
        var start = segment.start
        // A sparse trip owns its preceding corroborating fix too. That observation
        // must not extend an earlier pending flight across a long recording break.
        guard segment.isCruise else { return AnchorIndex(offset: start - 1) }
        while start > 0,
              legs[start - 1].isTransition,
              anchors[segment.start].timestamp.timeIntervalSince(anchors[start - 1].timestamp)
              <= Policy.maximumTransitionDuration
        {
            start -= 1
        }
        return AnchorIndex(offset: start)
    }

    private static func cruiseSegments(anchors: [LocationSample], legs: [Leg]) -> [Segment] {
        var result: [Segment] = []
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
                result.append(.cruise(start ..< index))
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
