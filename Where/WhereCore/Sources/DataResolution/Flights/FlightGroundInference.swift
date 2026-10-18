import Foundation

/// Confirms ground episodes from positive observations on one device. Sparse
/// stationary fixes and measured slow travel never borrow duration from silence.
enum FlightGroundInference {
    private typealias Policy = GPSCorrectionPolicy.Trajectory

    struct Episode {
        let start: Int
        let confirmation: Int
    }

    private enum Mode: CaseIterable {
        case stationary, sparseStationary, moving

        var duration: TimeInterval {
            switch self {
                case .stationary: Policy.minimumGroundDuration
                case .sparseStationary: GPSCorrectionPolicy.Ground.sparseMinimumDuration
                case .moving: GPSCorrectionPolicy.Ground.movingMinimumDuration
            }
        }

        var window: TimeInterval {
            switch self {
                case .stationary, .moving: Policy.maximumGroundWindow
                case .sparseStationary: GPSCorrectionPolicy.Ground.sparseMaximumWindow
            }
        }

        var gap: TimeInterval {
            switch self {
                case .stationary, .moving: Policy.maximumGroundGap
                case .sparseStationary: GPSCorrectionPolicy.Ground.sparseMaximumGap
            }
        }

        func accepts(_ sample: LocationSample, origin: LocationSample) -> Bool {
            guard sample.horizontalAccuracy <= GPSCorrectionPolicy.maximumHorizontalAccuracyMeters,
                  origin.horizontalAccuracy <= GPSCorrectionPolicy.maximumHorizontalAccuracyMeters
            else { return false }
            let speed = sample.motion?.speed
            if let speed {
                guard speed.metersPerSecond.isFinite, speed.accuracyMetersPerSecond.isFinite,
                      speed.metersPerSecond >= 0, speed.accuracyMetersPerSecond >= 0,
                      (speed.metersPerSecond + speed.accuracyMetersPerSecond) * 3.6
                      <= Policy.maximumGroundSpeedKMH else { return false }
            }
            switch self {
                case .moving: return speed != nil
                case .stationary, .sparseStationary:
                    return sample.coordinate.distance(to: origin.coordinate)
                        + sample.horizontalAccuracy + origin.horizontalAccuracy <= Policy
                        .groundRadiusMeters
            }
        }
    }

    static func episodes(anchors: [LocationSample], observations: [LocationSample]) -> [Episode] {
        guard anchors.count >= 3 else { return [] }
        var byLeg = [[LocationSample]](repeating: [], count: anchors.count - 1)
        var leg = 0
        for sample in observations {
            while leg + 1 < byLeg.count, sample.timestamp > anchors[leg + 1].timestamp {
                leg += 1
            }
            if sample.timestamp <= anchors[leg + 1].timestamp {
                byLeg[leg].append(sample)
                if leg + 1 < byLeg.count, sample.timestamp == anchors[leg + 1].timestamp {
                    byLeg[leg + 1].append(sample)
                }
            }
        }
        return anchors.indices.compactMap { start in
            var confirmation: Int?
            for mode in Mode.allCases where mode.accepts(anchors[start], origin: anchors[start]) {
                var end = start + 1
                while end < anchors.count,
                      anchors[end].timestamp.timeIntervalSince(anchors[start].timestamp) <= mode
                      .window,
                      anchors[end].timestamp.timeIntervalSince(anchors[end - 1].timestamp) <= mode
                      .gap,
                      upperSpeed(anchors[end - 1], anchors[end]) <= Policy.maximumGroundSpeedKMH,
                      mode.accepts(anchors[end], origin: anchors[start]),
                      byLeg[end - 1].allSatisfy({ mode.accepts($0, origin: anchors[start]) }),
                      zip(byLeg[end - 1], byLeg[end - 1].dropFirst())
                      .allSatisfy({ plausibleGroundPair(
                          $0,
                          $1,
                      ) })
                {
                    if end - start >= 2,
                       anchors[end].timestamp.timeIntervalSince(anchors[start].timestamp) >= mode
                       .duration
                    {
                        confirmation = min(confirmation ?? end, end)
                        break
                    }
                    end += 1
                }
            }
            return confirmation.map { Episode(start: start, confirmation: $0) }
        }
    }

    private static func upperSpeed(_ before: LocationSample, _ after: LocationSample) -> Double {
        (before.coordinate.distance(to: after.coordinate) + before.horizontalAccuracy + after
            .horizontalAccuracy)
            / after.timestamp.timeIntervalSince(before.timestamp) * 3.6
    }

    private static func plausibleGroundPair(
        _ before: LocationSample,
        _ after: LocationSample,
    ) -> Bool {
        let distance = max(
            0,
            before.coordinate.distance(to: after.coordinate)
                - before.horizontalAccuracy - after.horizontalAccuracy,
        )
        let seconds = after.timestamp.timeIntervalSince(before.timestamp)
        if seconds < Policy.sameObservationInterval { return distance == 0 }
        return distance / seconds * 3.6 <= Policy.maximumGroundSpeedKMH
    }
}
