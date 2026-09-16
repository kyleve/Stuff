import Foundation

/// Conservative jet-flight inference over independent device trajectories. All
/// thresholds are product policy, not measurements of a particular user's trip.
/// Short-interval fixes retain their identities but do not break motion baselines.
public struct FlightTrajectoryAnalyzer: Sendable {
    private enum Policy {
        static let maximumAccuracy = 250.0
        static let anchorInterval: TimeInterval = 60
        static let maximumBaseline: TimeInterval = 2 * 60 * 60
        static let coreSpeed = 450.0
        static let maximumSpeed = 1500.0
        static let minimumCoreDuration: TimeInterval = 3 * 60
        static let minimumProgress = 0.75
        static let transitionSpeed = 150.0
        static let transitionDuration: TimeInterval = 30 * 60
        static let groundRadius = 2000.0
        static let groundSpeed = 50.0
        static let groundDuration: TimeInterval = 10 * 60
        static let groundWindow: TimeInterval = 30 * 60
        static let groundGap: TimeInterval = 10 * 60
    }

    private struct Leg {
        let seconds: TimeInterval
        let distance: Double
        let lowerSpeed: Double
        let upperSpeed: Double

        var isCore: Bool {
            qualifies(minimumSpeed: Policy.coreSpeed)
        }

        var isTransition: Bool {
            qualifies(minimumSpeed: Policy.transitionSpeed)
        }

        private func qualifies(minimumSpeed: Double) -> Bool {
            seconds >= Policy.anchorInterval && seconds <= Policy.maximumBaseline
                && lowerSpeed >= minimumSpeed && upperSpeed <= Policy.maximumSpeed
        }
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
        var anchors: [LocationSample] = []
        for sample in usable {
            if let last = anchors.last,
               sample.timestamp.timeIntervalSince(last.timestamp) < Policy.anchorInterval
            { continue }
            anchors.append(sample)
        }
        guard anchors.count >= 3 else { return [] }
        let legs = zip(anchors, anchors.dropFirst()).map { Self.leg(from: $0, to: $1) }
        let cores = Self.cores(anchors: anchors, legs: legs)
        guard !cores.isEmpty else { return [] }
        let grounds = Self.grounds(anchors: anchors, legs: legs, observations: usable)
        var groups: [[Core]] = []
        for core in cores {
            if let previous = groups.last?.last,
               anchors[core.start].timestamp.timeIntervalSince(anchors[previous.end].timestamp)
               <= Policy.maximumBaseline,
               !grounds.contains(where: {
                   $0.start >= previous.end && $0.confirmation <= core.start
               })
            {
                groups[groups.count - 1].append(core)
            } else {
                groups.append([core])
            }
        }
        return groups.indices.map { index in
            assessment(
                cores: groups[index],
                anchors: anchors,
                legs: legs,
                usable: usable,
                grounds: grounds,
                nextStart: index + 1 < groups.count ? groups[index + 1][0].start : anchors.count,
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
        nextStart: Int,
        deviceID: RecordingDeviceID?,
        now: Date,
    ) -> FlightAssessment {
        let first = cores[0]
        let last = cores[cores.count - 1]
        let arrival = grounds.first { $0.start >= last.end && $0.confirmation <= nextStart }
        let departure = grounds.last { $0.confirmation <= first.start }
        var supportedLegs: Set<Int> = []
        for core in cores {
            supportedLegs.formUnion(core.start ..< core.end)
            var before = core.start
            while before > 0,
                  legs[before - 1].isTransition,
                  anchors[core.start].timestamp.timeIntervalSince(anchors[before - 1].timestamp)
                  <= Policy.transitionDuration
            {
                before -= 1
                supportedLegs.insert(before)
            }
            var after = core.end
            let limit = arrival?.start ?? nextStart - 1
            while after < limit,
                  legs[after].isTransition,
                  anchors[after + 1].timestamp.timeIntervalSince(anchors[core.end].timestamp)
                  <= Policy.transitionDuration
            {
                supportedLegs.insert(after)
                after += 1
            }
        }
        let groundIDs = Set([departure, arrival].compactMap(\.self).flatMap { ground in
            usable.filter {
                $0.timestamp >= anchors[ground.start].timestamp
                    && $0.timestamp <= anchors[ground.confirmation].timestamp
                    && Self.fitsGround($0, origin: anchors[ground.start])
            }.map(\.id)
        })
        let startIndex = supportedLegs.min() ?? first.start
        let endIndex = (supportedLegs.max() ?? last.end - 1) + 1
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
        let observationLimit = if let arrival {
            anchors[arrival.confirmation].timestamp
        } else if nextStart < anchors.count {
            anchors[nextStart].timestamp
        } else {
            now
        }
        let lastObservation = usable.last { $0.timestamp <= observationLimit } ?? latest
        let trailingMotionIsPlausible = anchors.last(where: {
            $0.timestamp <= lastObservation.timestamp
        }).map { Self.isPlausible(lastObservation, relativeTo: $0) } ?? false
        let observationStillCruising = trailingMotionIsPlausible
            && (anchors.last(where: {
                lastObservation.timestamp.timeIntervalSince($0.timestamp) >= Policy.anchorInterval
            }).map { Self.leg(from: $0, to: lastObservation).isCore } ?? false)
        let lastFlightAt = observationStillCruising
            ? max(latest.timestamp, lastObservation.timestamp) : latest.timestamp
        let progress: FlightAssessment.Progress = if let arrival {
            .completed(arrivedAt: anchors[arrival.start].timestamp)
        } else if observationStillCruising,
                  now.timeIntervalSince(lastFlightAt) < FlightAssessment.freshnessInterval
        {
            .flightLikely
        } else {
            .awaitingArrival
        }
        return FlightAssessment(
            id: .init(recordingDeviceID: deviceID, departureSampleID: earliest.id),
            startedAt: earliest.timestamp,
            lastObservationAt: lastObservation.timestamp,
            lastFlightAt: lastFlightAt,
            airborneSampleIDs: airborneIDs,
            groundSampleIDs: groundIDs,
            peakSpeedKMH: supportedLegs.map { legs[$0].distance / legs[$0].seconds * 3.6 }
                .max() ?? 0,
            progress: progress,
        )
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
            if index - start >= 2, seconds >= Policy.minimumCoreDuration,
               path > 0, progress / path >= Policy.minimumProgress
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
        var result: [Ground] = []
        for start in anchors.indices where fitsGround(anchors[start], origin: anchors[start]) {
            var end = start + 1
            while end < anchors.count,
                  anchors[end].timestamp.timeIntervalSince(anchors[start].timestamp)
                  <= Policy.groundWindow,
                  legs[end - 1].seconds <= Policy.groundGap,
                  legs[end - 1].upperSpeed <= Policy.groundSpeed,
                  fitsGround(anchors[end], origin: anchors[start]),
                  observationsByLeg[end - 1].allSatisfy({
                      fitsGround($0, origin: anchors[start])
                  })
            {
                if end - start >= 2,
                   anchors[end].timestamp.timeIntervalSince(anchors[start].timestamp)
                   >= Policy.groundDuration
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
        abs(sample.timestamp.timeIntervalSince(endpoint.timestamp)) < 1
            && sample.coordinate.distance(to: endpoint.coordinate)
            <= sample.horizontalAccuracy + endpoint.horizontalAccuracy
    }

    private static func fitsGround(_ sample: LocationSample, origin: LocationSample) -> Bool {
        if let speed = sample.motion?.speed,
           (speed.metersPerSecond + speed.accuracyMetersPerSecond) * 3.6 > Policy.groundSpeed
        { return false }
        return sample.coordinate.distance(to: origin.coordinate)
            + sample.horizontalAccuracy + origin.horizontalAccuracy <= Policy.groundRadius
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
        if seconds < 1 { return distance <= uncertainty }
        return max(0, distance - uncertainty) / seconds * 3.6 <= Policy.maximumSpeed
    }

    private static func leg(from before: LocationSample, to after: LocationSample) -> Leg {
        let seconds = after.timestamp.timeIntervalSince(before.timestamp)
        let distance = before.coordinate.distance(to: after.coordinate)
        let uncertainty = before.horizontalAccuracy + after.horizontalAccuracy
        return Leg(
            seconds: seconds,
            distance: distance,
            lowerSpeed: max(0, distance - uncertainty) / seconds * 3.6,
            upperSpeed: (distance + uncertainty) / seconds * 3.6,
        )
    }

    private static func isUsable(_ sample: LocationSample) -> Bool {
        sample.timestamp.timeIntervalSince1970.isFinite
            && sample.coordinate.latitude.isFinite && sample.coordinate.longitude.isFinite
            && (-90 ... 90).contains(sample.coordinate.latitude)
            && (-180 ... 180).contains(sample.coordinate.longitude)
            && sample.horizontalAccuracy.isFinite
            && (0 ... Policy.maximumAccuracy).contains(sample.horizontalAccuracy)
    }
}
