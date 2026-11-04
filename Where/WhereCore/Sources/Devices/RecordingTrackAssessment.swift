import Foundation

/// Positive motion or dwell evidence for one device in a bounded observation window.
/// Callers retain separate devices and gaps. Places explain dwell but never manufacture it.
public struct RecordingTrackAssessment: Hashable, Sendable {
    public enum ValidationError: Error {
        case multipleDevices
        case conflictingSampleIdentity(UUID)
    }

    public enum Activity: Hashable, Sendable {
        case moving
        case stationary
        case insufficient
        case implausible
    }

    public let activity: Activity
    public let supportingSampleIDs: Set<UUID>
    public let corroboratingPlaceIDs: Set<RecordingPlace.ID>

    public static func assess(
        observations: [RecordingObservation],
        places: [RecordingPlace],
    ) throws -> Self {
        var unique: [UUID: RecordingObservation] = [:]
        for observation in observations {
            if let existing = unique[observation.sample.id], existing != observation {
                throw ValidationError.conflictingSampleIdentity(observation.sample.id)
            }
            unique[observation.sample.id] = observation
        }
        let ordered = unique.values.sorted {
            if $0.sample.timestamp != $1.sample
                .timestamp { return $0.sample.timestamp < $1.sample.timestamp }
            return $0.sample.id.uuidString < $1.sample.id.uuidString
        }
        let empty = Self(
            activity: .insufficient,
            supportingSampleIDs: [],
            corroboratingPlaceIDs: [],
        )
        guard let first = ordered.first else { return empty }
        guard ordered.allSatisfy({ $0.deviceID == first.deviceID }) else {
            throw ValidationError.multipleDevices
        }
        // Inaccurate intervening observations cannot be silently discarded to invent coherence.
        guard ordered
            .allSatisfy({
                $0.sample.horizontalAccuracy <= RecordingEvidencePolicy.maximumAccuracyMeters })
        else { return empty }
        var anchors: [RecordingObservation] = []
        for observation in ordered {
            if let last = anchors.last,
               observation.sample.timestamp
               .timeIntervalSince(last.sample.timestamp) < RecordingEvidencePolicy
               .minimumAnchorInterval
            { continue }
            anchors.append(observation)
        }
        guard anchors.count >= RecordingEvidencePolicy.minimumObservationCount,
              let last = anchors.last
        else { return empty }
        let samples = Set(anchors.map(\.sample.id))
        var pathDistance = 0.0
        for (left, right) in zip(ordered, ordered.dropFirst()) {
            let elapsed = right.sample.timestamp.timeIntervalSince(left.sample.timestamp)
            guard elapsed <= RecordingEvidencePolicy.maximumObservationGap else { return empty }
            let distance = left.sample.coordinate.distance(to: right.sample.coordinate)
            let lowerDistance = max(
                0,
                distance - left.sample.horizontalAccuracy - right.sample.horizontalAccuracy,
            )
            guard lowerDistance <= max(0, elapsed) * RecordingEvidencePolicy
                .maximumPlausibleSpeedMetersPerSecond
            else {
                return Self(
                    activity: .implausible,
                    supportingSampleIDs: samples,
                    corroboratingPlaceIDs: [],
                )
            }
            pathDistance += distance
        }
        let duration = last.sample.timestamp.timeIntervalSince(first.sample.timestamp)
        let displacement = first.sample.coordinate.distance(to: last.sample.coordinate)
        let lowerDisplacement = max(
            0,
            displacement - first.sample.horizontalAccuracy - last.sample.horizontalAccuracy,
        )
        let movingLegs = zip(anchors, anchors.dropFirst()).count(where: { left, right in
            left.sample.coordinate.distance(to: right.sample.coordinate)
                - left.sample.horizontalAccuracy - right.sample.horizontalAccuracy
                >= RecordingEvidencePolicy.minimumMovingLegDisplacementMeters
        })
        if duration >= RecordingEvidencePolicy.minimumMovingDuration,
           lowerDisplacement >= RecordingEvidencePolicy.minimumMovingDisplacementMeters,
           movingLegs >= RecordingEvidencePolicy.minimumMovingLegs,
           pathDistance > 0,
           displacement / pathDistance >= RecordingEvidencePolicy.minimumProgressRatio
        {
            return Self(activity: .moving, supportingSampleIDs: samples, corroboratingPlaceIDs: [])
        }
        let stationary = ordered.allSatisfy { left in
            ordered.allSatisfy { right in
                left.sample.coordinate.distance(to: right.sample.coordinate)
                    <= RecordingEvidencePolicy.stationaryRadiusMeters
                    + left.sample.horizontalAccuracy + right.sample.horizontalAccuracy
            }
        }
        guard duration >= RecordingEvidencePolicy.minimumStationaryDuration,
              stationary else { return empty }
        let matching = places.filter { place in
            ordered.allSatisfy { observation in
                place.validity.contains(observation.sample.timestamp)
                    && place.coordinate.distance(to: observation.sample.coordinate)
                    <= RecordingEvidencePolicy.placeRadiusMeters + observation.sample
                    .horizontalAccuracy
            }
        }
        return Self(
            activity: .stationary,
            supportingSampleIDs: samples,
            corroboratingPlaceIDs: Set(matching.map(\.id)),
        )
    }
}
