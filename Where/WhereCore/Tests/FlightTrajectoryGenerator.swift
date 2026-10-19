import Foundation
import RegionKit
import WhereCore

/// Generates a known journey first, then samples it with reproducible recording
/// variations. Expected ground identities come from the journey, never the detector.
enum FlightTrajectoryGenerator {
    enum Profile: String, CaseIterable {
        case denseJet, sparseJet, shortSparseJet, mixedSampling, longHaul, connections
        case overnightDateLine, stationaryDrift, clusteredDrift, road, fastGround, slowerAircraft
    }

    struct JourneyPoint {
        let minutes: Double
        let distanceKM: Double
        let isGround: Bool
    }

    struct Scenario {
        let samples: [LocationSample]
        let groundIDs: Set<LocationSample.ID>
        let expectedFlights: Int
        let requiredEvidenceIDs: Set<LocationSample.ID>
        let now: Date
        let description: String
    }

    /// SplitMix64 gives each profile/seed a stable, independently replayable stream.
    struct Random: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }
    }

    static func make(profile: Profile, seed: UInt64) -> Scenario {
        var random = Random(seed: seed)
        let scale = Double.random(in: 0.95 ... 1.05, using: &random)
        let timeScale = Double.random(in: 1.05 ... 1.2, using: &random)
        let points = journey(profile: profile, scale: scale)
        let latitude = profile == .overnightDateLine ? 65.0 : Double.random(
            in: -55 ... 55,
            using: &random,
        )
        let longitude = profile == .overnightDateLine ? 179.0 : Double.random(
            in: -170 ... 170,
            using: &random,
        )
        let origin = Coordinate(latitude: latitude, longitude: longitude)
        let bearing = profile == .overnightDateLine ? 90.0 : Double.random(
            in: 0 ... 360,
            using: &random,
        )
        let offset = profile == .overnightDateLine ? 23.0 * 60 : Double.random(
            in: 0 ... 60,
            using: &random,
        )
        let base = FlightTrajectoryFixtures.start.addingTimeInterval(offset * 60)
        let clusterOffsetKM = profile == .clusteredDrift
            ? Double.random(in: 15 ... 25, using: &random) : 0
        var groundIDs: Set<LocationSample.ID> = []
        let samples = points.enumerated().map { index, point in
            let sampleID = FlightTrajectoryFixtures.sampleID(index + 1)
            if point.isGround { groundIDs.insert(sampleID) }
            let routeCoordinate = coordinate(
                from: origin,
                bearing: bearing,
                distanceKM: point.distanceKM,
            )
            let bend = profile == .denseJet && !point.isGround
                ? 3 * sin(point.distanceKM / (450 * scale) * .pi) : 0
            let trueCoordinate = coordinate(
                from: routeCoordinate,
                bearing: bearing + 90,
                distanceKM: bend,
            )
            // Three callbacks share a remote GPS error while the underlying
            // journey stays stationary. Returning fixes bound the brief outage.
            let observedCenter = if profile == .clusteredDrift && (2 ... 4).contains(index) {
                coordinate(from: trueCoordinate, bearing: bearing, distanceKM: clusterOffsetKM)
            } else {
                trueCoordinate
            }
            let noiseMeters = Double.random(in: 0 ... 15, using: &random)
            let coordinate = coordinate(
                from: observedCenter,
                bearing: Double.random(in: 0 ... 360, using: &random),
                distanceKM: noiseMeters / 1000,
            )
            let accuracy = Double.random(in: 20 ... 100, using: &random)
            let sensor: LocationMotion? = Bool.random(using: &random) && point.isGround
                ? .init(
                    speed: .init(metersPerSecond: 0, accuracyMetersPerSecond: 1),
                    altitude: nil,
                ) : nil
            return LocationSample(
                id: sampleID,
                timestamp: base.addingTimeInterval(point.minutes * timeScale * 60),
                coordinate: coordinate,
                horizontalAccuracy: accuracy,
                source: Bool.random(using: &random) ? .gpsVisit : .gpsSignificantChange,
                recordingDeviceID: FlightTrajectoryFixtures.device,
                motion: sensor,
            )
        }
        let expectedFlights = switch profile {
            case .denseJet, .sparseJet, .shortSparseJet, .mixedSampling, .longHaul,
                 .overnightDateLine: 1
            case .connections: 2
            case .stationaryDrift, .clusteredDrift, .road, .fastGround, .slowerAircraft: 0
        }
        return Scenario(
            samples: samples,
            groundIDs: groundIDs,
            expectedFlights: expectedFlights,
            requiredEvidenceIDs: profile == .denseJet
                ? groundIDs.union([
                    FlightTrajectoryFixtures.sampleID(4),
                    FlightTrajectoryFixtures.sampleID(7),
                ]) : groundIDs,
            now: base
                .addingTimeInterval(points[points.count - 1].minutes * timeScale * 60),
            description: "profile=\(profile.rawValue), seed=\(seed), latitude=\(latitude), longitude=\(longitude), bearing=\(bearing), scale=\(scale), timeScale=\(timeScale), clusterOffsetKM=\(clusterOffsetKM)",
        )
    }

    private static func journey(profile: Profile, scale: Double) -> [JourneyPoint] {
        func point(_ minute: Double, _ distance: Double, ground: Bool) -> JourneyPoint {
            JourneyPoint(minutes: minute, distanceKM: distance * scale, isGround: ground)
        }
        let departure = [point(0, 0, ground: true), point(5, 0, ground: true)]
        switch profile {
            case .shortSparseJet:
                return departure + [
                    point(25, 200, ground: true),
                    point(30, 200, ground: true),
                    point(35, 200, ground: true),
                ]
            case .clusteredDrift:
                return [0.0, 5, 6.5, 7.5, 8.5, 10, 15, 20].map { point($0, 0, ground: true) }
            case .sparseJet, .mixedSampling, .overnightDateLine, .connections:
                var points = departure
                if profile == .mixedSampling { points.append(point(140, 2000, ground: false)) }
                points += [
                    point(275, 4000, ground: true),
                    point(280, 4000, ground: true),
                    point(285, 4000, ground: true),
                ]
                if profile == .connections {
                    points += [
                        point(555, 0, ground: true),
                        point(560, 0, ground: true),
                        point(565, 0, ground: true),
                    ]
                }
                return points
            case .longHaul:
                return departure + [
                    point(805, 12000, ground: true),
                    point(810, 12000, ground: true),
                    point(815, 12000, ground: true),
                ]
            case .denseJet:
                return departure + [point(10, 0, ground: true)]
                    + (0 ... 6).map { point(15 + Double($0) * 5, Double($0) * 75, ground: $0 == 6) }
                    + [point(50, 450, ground: true), point(55, 450, ground: true)]
            case .stationaryDrift, .road, .fastGround, .slowerAircraft:
                let speed: Double
                switch profile {
                    case .stationaryDrift: speed = 0
                    case .road: speed = 30
                    case .fastGround: speed = 300
                    case .slowerAircraft: speed = 350
                    case .denseJet, .sparseJet, .shortSparseJet, .mixedSampling, .longHaul,
                         .connections,
                         .overnightDateLine, .clusteredDrift:
                        preconditionFailure("Only non-jet profiles use ground/slow speeds")
                }
                return (0 ... 12).map { point(
                    Double($0) * 5,
                    Double($0) * speed / 12,
                    ground: profile != .slowerAircraft,
                ) }
        }
    }

    /// Spherical destination calculation is independent of the detector's haversine distance.
    private static func coordinate(
        from origin: Coordinate,
        bearing: Double,
        distanceKM: Double,
    ) -> Coordinate {
        let angular = distanceKM / 6371
        let course = bearing * .pi / 180
        let latitude = origin.latitude * .pi / 180
        let longitude = origin.longitude * .pi / 180
        let targetLatitude =
            asin(sin(latitude) * cos(angular) + cos(latitude) * sin(angular) * cos(course))
        let targetLongitude = longitude + atan2(
            sin(course) * sin(angular) * cos(latitude),
            cos(angular) - sin(latitude) * sin(targetLatitude),
        )
        let degrees = targetLongitude * 180 / .pi
        let wrapped = (degrees + 540).truncatingRemainder(dividingBy: 360) - 180
        return Coordinate(latitude: targetLatitude * 180 / .pi, longitude: wrapped)
    }

    /// Bounded deletion minimization preserves the failing predicate and never
    /// writes private data. The returned synthetic trace is suitable for a regression.
    static func reduced(
        _ samples: [LocationSample],
        fails: ([LocationSample]) -> Bool,
    ) -> [LocationSample] {
        var result = samples
        var attempts = 0
        var index = 0
        while index < result.count, attempts < 100 {
            var candidate = result
            candidate.remove(at: index)
            attempts += 1
            if fails(candidate) { result = candidate } else { index += 1 }
        }
        return result
    }
}
