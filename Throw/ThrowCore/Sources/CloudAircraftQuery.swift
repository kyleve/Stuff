import Foundation

public struct CloudAircraftQueryPlan: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let coarseCenter: GeoCoordinate
    public let transmittedRadius: NauticalMiles

    public init(coarseCenter: GeoCoordinate, transmittedRadius: NauticalMiles) {
        self.coarseCenter = coarseCenter
        self.transmittedRadius = transmittedRadius
    }

    public var description: String {
        "<CloudAircraftQueryPlan center=<redacted>>"
    }

    public var debugDescription: String {
        description
    }
}

public enum CloudAircraftQuery {
    public static let paddingNauticalMiles = 10.0
    public static let maximumRadiusNauticalMiles = 250.0
    public static let trueSkyGroundRangeNauticalMiles = 240.0

    public static func plan(for query: AircraftQuery) throws -> CloudAircraftQueryPlan {
        let latitude = roundedTenth(query.center.latitude)
        let longitude = min(180, max(-180, roundedTenth(query.center.longitude)))
        let radius: Double = switch query.viewport {
            case let .map(viewport):
                min(
                    viewport.radius.value + paddingNauticalMiles,
                    maximumRadiusNauticalMiles,
                )
            case .trueSky:
                maximumRadiusNauticalMiles
        }
        return try CloudAircraftQueryPlan(
            coarseCenter: GeoCoordinate(latitude: latitude, longitude: longitude),
            transmittedRadius: NauticalMiles(value: radius),
        )
    }

    public static func postFilter(
        _ observations: [AircraftObservation],
        for query: AircraftQuery,
    ) throws -> [AircraftObservation] {
        let engine = ProjectionEngine()
        var filtered: [AircraftObservation] = []
        filtered.reserveCapacity(observations.count)
        for observation in observations {
            try Task.checkCancellation()
            switch query.viewport {
                case let .map(viewport):
                    if observation.airborneState == .ground, query.includeGroundAircraft == false {
                        continue
                    }
                    let position = try engine.greatCirclePosition(
                        from: query.center,
                        to: observation.coordinate,
                    )
                    if position.distance <= viewport.radius {
                        filtered.append(observation)
                    }
                case let .trueSky(viewport):
                    guard observation.airborneState != .ground else { continue }
                    guard let altitude = observation.preferredSkyAltitude else { continue }
                    let groundPosition = try engine.greatCirclePosition(
                        from: query.observer.coordinate,
                        to: observation.coordinate,
                    )
                    guard groundPosition.distance.value <= trueSkyGroundRangeNauticalMiles else {
                        continue
                    }
                    let anchor = GeodeticAnchor(
                        coordinate: observation.coordinate,
                        altitude: altitude,
                        altitudeQuality: observation.skyAltitudeQuality,
                    )
                    guard let horizontal = try engine.horizontalPosition(
                        observer: query.observer,
                        target: anchor,
                    ), horizontal.elevation.degrees >= viewport.minimumElevation.degrees
                    else {
                        continue
                    }
                    filtered.append(observation)
            }
        }
        return filtered
    }

    public static func pathComponent(for value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func roundedTenth(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
