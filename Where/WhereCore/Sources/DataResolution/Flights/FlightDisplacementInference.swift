import Foundation

/// Recognizes sparse journeys from corroborated positions and elapsed time.
/// This establishes travel between endpoints, never airborne sample identities.
enum FlightDisplacementInference {
    private typealias Trajectory = GPSCorrectionPolicy.Trajectory
    private typealias Policy = GPSCorrectionPolicy.Displacement

    /// The analyzer supplies usable, ordered, independent anchors from one device.
    static func supportsFlight(
        from departure: LocationSample,
        to destination: LocationSample,
        previous: LocationSample,
        next: LocationSample,
        observations: [LocationSample],
    ) -> Bool {
        let seconds = destination.timestamp.timeIntervalSince(departure.timestamp)
        let distance = departure.coordinate.distance(to: destination.coordinate)
        let uncertainty = departure.horizontalAccuracy + destination.horizontalAccuracy
        guard Set([previous.id, departure.id, destination.id, next.id]).count == 4,
              seconds >= Trajectory.minimumAnchorInterval,
              seconds <= Trajectory.maximumCorroboratingGap,
              distance - uncertainty >= Policy.minimumDistanceMeters,
              (distance - uncertainty) / seconds * 3.6 >= Trajectory.minimumCruiseSpeedKMH,
              (distance + uncertainty) / seconds * 3.6 <= Trajectory.maximumPlausibleSpeedKMH,
              corroborates(previous, endpoint: departure),
              corroborates(next, endpoint: destination) else { return false }

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
            && seconds <= Policy.maximumSupportInterval
            && sample.coordinate.distance(to: endpoint.coordinate)
            + sample.horizontalAccuracy + endpoint.horizontalAccuracy
            <= Policy.maximumSupportDistanceMeters
            && isPlausible(sample, relativeTo: endpoint)
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
