import Foundation

/// Corroboration for a cruise endpoint that would otherwise retain uncertain presence.
/// A recording gap supports a reviewed suggestion; it never becomes an observed leg.
public struct FlightEndpointInference: Hashable, Sendable {
    public enum Reason: Hashable, Sendable {
        case recordingGap(duration: TimeInterval, averageSpeedKMH: Double)
        case recordedSpeed(lowerBoundKMH: Double)
    }

    public let sampleID: UUID
    public let reason: Reason

    public init(sampleID: UUID, reason: Reason) {
        self.sampleID = sampleID
        self.reason = reason
    }

    /// The analyzer supplies an already validated, sustained cruise core on one device.
    static func reason(
        cruise: [LocationSample],
        previous: LocationSample?,
        endpointObservations: [LocationSample],
    ) -> Reason? {
        typealias Policy = GPSCorrectionPolicy.Trajectory
        guard let first = cruise.first, let last = cruise.last else { return nil }
        let speeds = endpointObservations.compactMap { sample -> LocationMotion.Speed? in
            guard let speed = sample.motion?.speed,
                  speed.metersPerSecond.isFinite, speed.metersPerSecond >= 0,
                  speed.accuracyMetersPerSecond.isFinite, speed.accuracyMetersPerSecond >= 0
            else { return nil }
            return speed
        }
        // A reliable slow reading contradicts an already-airborne endpoint, even
        // when the next few minutes include a genuine takeoff.
        guard !speeds.contains(where: {
            ($0.metersPerSecond + $0.accuracyMetersPerSecond) * 3.6
                < Policy.minimumCruiseSpeedKMH
        }) else { return nil }
        if let speed = speeds.first(where: {
            ($0.metersPerSecond - $0.accuracyMetersPerSecond) * 3.6
                >= Policy.minimumCruiseSpeedKMH
                && ($0.metersPerSecond + $0.accuracyMetersPerSecond) * 3.6
                <= Policy.maximumPlausibleSpeedKMH
        }) {
            return .recordedSpeed(lowerBoundKMH:
                (speed.metersPerSecond - speed.accuracyMetersPerSecond) * 3.6)
        }
        guard let previous,
              last.timestamp.timeIntervalSince(first.timestamp)
              >= Policy.minimumResumedCruiseDuration else { return nil }
        let seconds = first.timestamp.timeIntervalSince(previous.timestamp)
        let distance = previous.coordinate.distance(to: first.coordinate)
        let uncertainty = previous.horizontalAccuracy + first.horizontalAccuracy
        let lower = max(0, distance - uncertainty) / seconds * 3.6
        let upper = (distance + uncertainty) / seconds * 3.6
        let cruiseDistance = zip(cruise, cruise.dropFirst()).reduce(0.0) {
            $0 + $1.0.coordinate.distance(to: $1.1.coordinate)
        }
        // Preserve the two-hour observed-leg cap. Only a bounded long gap with
        // flight-speed displacement and continuing directed cruise corroborates
        // this first fix. No absent points or earlier endpoints are corrected.
        guard seconds > Policy.maximumLegInterval,
              seconds <= Policy.maximumCorroboratingGap,
              lower >= Policy.minimumCruiseSpeedKMH,
              upper <= Policy.maximumPlausibleSpeedKMH,
              previous.coordinate.distance(to: last.coordinate) / (distance + cruiseDistance)
              >= Policy.minimumDirectProgressRatio else { return nil }
        return .recordingGap(duration: seconds, averageSpeedKMH: distance / seconds * 3.6)
    }
}
