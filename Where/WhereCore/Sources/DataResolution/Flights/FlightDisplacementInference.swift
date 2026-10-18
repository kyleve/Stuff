import Foundation

/// Recognizes sparse journeys from corroborated positions and elapsed time.
/// This establishes travel between endpoints, never airborne sample identities.
enum FlightDisplacementInference {
    private typealias Trajectory = GPSCorrectionPolicy.Trajectory
    private typealias Displacement = GPSCorrectionPolicy.Displacement

    /// Anchor legs covered by a corroborated journey and its preceding support.
    struct Window {
        let legs: Range<Int>
        let previous: Int
    }

    /// Search bounded windows independently of callback density. Ground episodes
    /// stop the search before a candidate can absorb a known connection.
    static func windows(
        anchors: [LocationSample],
        observations: [LocationSample],
        grounds: [ClosedRange<Int>],
        cruise: [Range<Int>],
    ) -> [Window] {
        guard anchors.count >= 4 else { return [] }
        var previous = [[Int]](repeating: [], count: anchors.count)
        var next = previous
        for index in anchors.indices {
            var candidate = index - 1
            while candidate >= 0,
                  anchors[index].timestamp.timeIntervalSince(anchors[candidate].timestamp)
                  <= Displacement.maximumSupportInterval
            {
                if corroborates(anchors[candidate], endpoint: anchors[index]) {
                    previous[index].append(candidate)
                    next[candidate].append(index)
                }
                candidate -= 1
            }
        }
        // Pre-index raw observations so candidate validation touches only its
        // local window, including callbacks omitted from independent anchors.
        let lower = anchors.map { anchor in
            observations.flightPartitionIndex { $0.timestamp >= anchor.timestamp }
        }
        let upper = anchors.map { anchor in
            observations.flightPartitionIndex { $0.timestamp > anchor.timestamp }
        }
        var result: [Window] = []
        var groundIndex = 0
        var cruiseIndex = 0
        for start in anchors.indices where !previous[start].isEmpty {
            var end = start + 1
            while groundIndex < grounds.count,
                  grounds[groundIndex].lowerBound <= start
            {
                groundIndex += 1
            }
            while cruiseIndex < cruise.count,
                  cruise[cruiseIndex].upperBound <= start
            {
                cruiseIndex += 1
            }
            let groundStop = groundIndex < grounds.count ? grounds[groundIndex].upperBound : anchors
                .endIndex
            let cruiseStop = cruiseIndex < cruise.count ? cruise[cruiseIndex].lowerBound : anchors
                .endIndex
            let stop = min(groundStop, cruiseStop)
            while end < anchors.count,
                  anchors[end].timestamp.timeIntervalSince(anchors[start].timestamp)
                  <= Trajectory.maximumCorroboratingGap
            {
                if end > stop { break }
                defer { end += 1 }
                // Existing observed cruise already explains this interval. Windows
                // may meet a cruise endpoint, but must not absorb its ground lead-in.
                guard !next[end].isEmpty,
                      qualifies(from: anchors[start], to: anchors[end]) else { continue }
                var support: Int?
                for before in previous[start] {
                    for after in next[end] {
                        if supportsFlight(
                            from: anchors[start],
                            to: anchors[end],
                            previous: anchors[before],
                            next: anchors[after],
                            observations: observations[lower[before] ..< upper[after]],
                        ) {
                            support = before
                            break
                        }
                    }
                    if support != nil { break }
                }
                if let support {
                    result.append(Window(legs: start ..< end, previous: support))
                    // The first supported destination preserves subsequent ground
                    // dwell instead of stretching travel through its confirmation.
                    break
                }
            }
        }
        // Prefer the latest supported departure for an identical destination.
        // Earlier stationary fixes corroborate departure; they are not travel.
        var destinations: Set<Int> = []
        return result.reversed().filter { destinations.insert($0.legs.upperBound).inserted }
            .reversed()
    }

    private static func qualifies(
        from departure: LocationSample,
        to destination: LocationSample,
    ) -> Bool {
        let seconds = destination.timestamp.timeIntervalSince(departure.timestamp)
        let distance = departure.coordinate.distance(to: destination.coordinate)
        let uncertainty = departure.horizontalAccuracy + destination.horizontalAccuracy
        return seconds >= Displacement.minimumTravelDuration
            && seconds <= Trajectory.maximumCorroboratingGap
            && (distance - uncertainty) / seconds * 3.6 >= Trajectory.minimumCruiseSpeedKMH
            && (distance + uncertainty) / seconds * 3.6 <= Trajectory.maximumPlausibleSpeedKMH
    }

    /// The analyzer supplies usable, ordered, independent anchors from one device.
    static func supportsFlight(
        from departure: LocationSample,
        to destination: LocationSample,
        previous: LocationSample,
        next: LocationSample,
        observations: some Collection<LocationSample>,
    ) -> Bool {
        guard Set([previous.id, departure.id, destination.id, next.id]).count == 4,
              qualifies(from: departure, to: destination),
              corroborates(previous, endpoint: departure, oppositeEndpoint: destination),
              corroborates(next, endpoint: destination, oppositeEndpoint: departure)
        else { return false }

        // A lone remote fix or an immediate return cannot corroborate a destination.
        // Dense callbacks also retain their veto: anchor thinning must not hide a
        // contradictory observation beside either otherwise plausible endpoint.
        let anchors = [previous, departure, destination, next]
        return observations.allSatisfy { sample in
            guard sample.timestamp >= previous.timestamp,
                  sample.timestamp <= next.timestamp else { return true }
            return anchors.allSatisfy { isPlausible(sample, relativeTo: $0) }
        }
    }

    private static func corroborates(_ sample: LocationSample, endpoint: LocationSample) -> Bool {
        let seconds = abs(sample.timestamp.timeIntervalSince(endpoint.timestamp))
        return seconds >= Trajectory.minimumAnchorInterval
            && seconds <= Displacement.maximumSupportInterval
            && sample.coordinate.distance(to: endpoint.coordinate)
            + sample.horizontalAccuracy + endpoint.horizontalAccuracy
            <= Displacement.maximumSupportDistanceMeters
            && isPlausible(sample, relativeTo: endpoint)
    }

    private static func corroborates(
        _ sample: LocationSample,
        endpoint: LocationSample,
        oppositeEndpoint: LocationSample,
    ) -> Bool {
        // The absolute support radius can span both ends of a short journey.
        // Require unambiguous support for this end so alternating GPS jumps
        // cannot corroborate one another, even at a plausible travel speed.
        let ownUpperDistance = sample.coordinate.distance(to: endpoint.coordinate)
            + sample.horizontalAccuracy + endpoint.horizontalAccuracy
        let oppositeLowerDistance = sample.coordinate.distance(to: oppositeEndpoint.coordinate)
            - sample.horizontalAccuracy - oppositeEndpoint.horizontalAccuracy
        return ownUpperDistance < oppositeLowerDistance && corroborates(sample, endpoint: endpoint)
    }

    private static func isPlausible(
        _ sample: LocationSample,
        relativeTo anchor: LocationSample,
    ) -> Bool {
        let seconds = abs(sample.timestamp.timeIntervalSince(anchor.timestamp))
        let distance = sample.coordinate.distance(to: anchor.coordinate)
        let uncertainty = sample.horizontalAccuracy + anchor.horizontalAccuracy
        if seconds < Trajectory.sameObservationInterval { return distance <= uncertainty }
        return max(0, distance - uncertainty) / seconds * 3.6
            <= Trajectory.maximumPlausibleSpeedKMH
    }
}

extension [LocationSample] {
    fileprivate func flightPartitionIndex(_ predicate: (Element) -> Bool) -> Int {
        var lower = startIndex
        var upper = endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if predicate(self[middle]) { upper = middle } else { lower = middle + 1 }
        }
        return lower
    }
}
