import Foundation

/// Classifies ambient arrival and departure estimates from route and motion data.
public struct FlightActivityClassifier: Sendable {
    public static let localRadius = try! NauticalMiles(value: 50)
    private static let inferredRadius = try! NauticalMiles(value: 15)

    private let airportCatalog: AirportCatalog
    private let engine = ProjectionEngine()

    public init(airportCatalog: AirportCatalog) {
        self.airportCatalog = airportCatalog
    }

    public func activity(
        for observation: AircraftObservation,
        observer: ObserverPosition,
        route: FlightRoute?,
    ) throws -> FlightActivity {
        guard observation.airborneState != .ground else { return .overflight }
        if let route,
           let confirmed = try confirmedActivity(
               observation: observation,
               observer: observer,
               route: route,
           )
        {
            return confirmed
        }
        return try inferredActivity(observation: observation) ?? .overflight
    }

    private func confirmedActivity(
        observation: AircraftObservation,
        observer: ObserverPosition,
        route: FlightRoute,
    ) throws -> FlightActivity? {
        let origin = try localAirport(for: route.origin, observer: observer)
        let destination = try localAirport(for: route.destination, observer: observer)
        switch (origin, destination) {
            case (nil, nil): return nil
            case let (origin?, nil): return try departure(
                    observation,
                    airport: origin,
                    certainty: .confirmed,
                )
            case let (nil, destination?): return try arrival(
                    observation,
                    airport: destination,
                    certainty: .confirmed,
                )
            case let (origin?, destination?):
                return try chooseBothLocal(
                    observation,
                    origin: origin,
                    destination: destination,
                )
        }
    }

    private func localAirport(
        for code: AirportCode,
        observer: ObserverPosition,
    ) throws -> AirportRecord? {
        guard let airport = try airportCatalog.airport(for: code, near: observer)
        else { return nil }
        let distance = try airportCatalog.distance(
            from: observer.coordinate,
            to: airport.coordinate,
        )
        return distance <= Self.localRadius ? airport : nil
    }

    private func chooseBothLocal(
        _ observation: AircraftObservation,
        origin: AirportRecord,
        destination: AirportRecord,
    ) throws -> FlightActivity {
        if let verticalRate = observation.verticalRateFeetPerMinute {
            if verticalRate <= -200 { return try arrival(
                observation,
                airport: destination,
                certainty: .confirmed,
            ) }
            if verticalRate >= 200 { return try departure(
                observation,
                airport: origin,
                certainty: .confirmed,
            ) }
        }
        if let track = observation.groundTrack {
            let towardDestination = try courseDifference(
                track,
                engine.greatCirclePosition(
                    from: observation.coordinate,
                    to: destination.coordinate,
                ).initialBearing,
            )
            let awayFromOrigin = try courseDifference(
                track,
                engine.greatCirclePosition(
                    from: origin.coordinate,
                    to: observation.coordinate,
                ).initialBearing,
            )
            if towardDestination != awayFromOrigin {
                return towardDestination < awayFromOrigin
                    ? try arrival(observation, airport: destination, certainty: .confirmed)
                    : try departure(observation, airport: origin, certainty: .confirmed)
            }
        }
        let originDistance = try distance(observation, airport: origin)
        let destinationDistance = try distance(observation, airport: destination)
        return originDistance <= destinationDistance
            ? try departure(observation, airport: origin, certainty: .confirmed)
            : try arrival(observation, airport: destination, certainty: .confirmed)
    }

    private func inferredActivity(observation: AircraftObservation) throws -> FlightActivity? {
        guard let altitude = observation.preferredSkyAltitude,
              let verticalRate = observation.verticalRateFeetPerMinute,
              abs(verticalRate) >= 300,
              let track = observation.groundTrack
        else { return nil }
        let nearby = try airportCatalog.airports(
            within: Self.inferredRadius,
            of: observation.coordinate,
        )
        var candidates: [(airport: AirportRecord, distance: NauticalMiles, difference: Double)] = []
        for airport in nearby {
            guard let airportElevation = airport.elevation else { continue }
            let agl = altitude.feet - airportElevation.feet
            guard agl >= 0, agl <= 6000 else { continue }
            let airportDistance = try distance(observation, airport: airport)
            let expectedBearing = try verticalRate < 0
                ? engine.greatCirclePosition(
                    from: observation.coordinate,
                    to: airport.coordinate,
                ).initialBearing
                : engine.greatCirclePosition(
                    from: airport.coordinate,
                    to: observation.coordinate,
                ).initialBearing
            let difference = courseDifference(track, expectedBearing)
            guard difference <= 30 else { continue }
            if airportDistance.value <= 8,
               let runway = airport.longestOpenRunway,
               try runwayDifference(track, runway: runway) > 25
            {
                continue
            }
            candidates.append((airport, airportDistance, difference))
        }
        guard let selected = candidates.min(by: {
            if $0.difference != $1.difference { return $0.difference < $1.difference }
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            return $0.airport.id.rawValue < $1.airport.id.rawValue
        }) else { return nil }
        return verticalRate < 0
            ? try arrival(observation, airport: selected.airport, certainty: .inferred)
            : try departure(observation, airport: selected.airport, certainty: .inferred)
    }

    private func arrival(
        _ observation: AircraftObservation,
        airport: AirportRecord,
        certainty: FlightActivityCertainty,
    ) throws -> FlightActivity {
        let context = try context(observation, airport: airport)
        let isClose = context.aircraftDistance.value <= 25
        let isLow = agl(observation, airport: airport).map { $0 <= 10000 } ?? false
        let descends = (observation.verticalRateFeetPerMinute ?? 0) <= -200
        let pointsToward = try aligned(observation, toward: airport.coordinate, tolerance: 30)
        return .arrival(
            context,
            isClose && isLow && (descends || pointsToward) ? .approach : .inbound,
            certainty,
        )
    }

    private func departure(
        _ observation: AircraftObservation,
        airport: AirportRecord,
        certainty: FlightActivityCertainty,
    ) throws -> FlightActivity {
        let context = try context(observation, airport: airport)
        let isClose = context.aircraftDistance.value <= 25
        let isLow = agl(observation, airport: airport).map { $0 <= 10000 } ?? false
        let climbs = (observation.verticalRateFeetPerMinute ?? 0) >= 200
        let pointsAway = try aligned(observation, awayFrom: airport.coordinate, tolerance: 30)
        return .departure(
            context,
            isClose && isLow && (climbs || pointsAway) ? .initialClimb : .outbound,
            certainty,
        )
    }

    private func context(
        _ observation: AircraftObservation,
        airport: AirportRecord,
    ) throws -> AirportActivityContext {
        try AirportActivityContext(
            airport: airport,
            aircraftDistance: distance(observation, airport: airport),
        )
    }

    private func distance(
        _ observation: AircraftObservation,
        airport: AirportRecord,
    ) throws -> NauticalMiles {
        try airportCatalog.distance(from: observation.coordinate, to: airport.coordinate)
    }

    private func agl(_ observation: AircraftObservation, airport: AirportRecord) -> Double? {
        guard let altitude = observation.preferredSkyAltitude,
              let airportElevation = airport.elevation
        else { return nil }
        return altitude.feet - airportElevation.feet
    }

    private func aligned(
        _ observation: AircraftObservation,
        toward coordinate: GeoCoordinate,
        tolerance: Double,
    ) throws -> Bool {
        guard let track = observation.groundTrack else { return false }
        let bearing = try engine.greatCirclePosition(from: observation.coordinate, to: coordinate)
            .initialBearing
        return courseDifference(track, bearing) <= tolerance
    }

    private func aligned(
        _ observation: AircraftObservation,
        awayFrom coordinate: GeoCoordinate,
        tolerance: Double,
    ) throws -> Bool {
        guard let track = observation.groundTrack else { return false }
        let bearing = try engine.greatCirclePosition(from: coordinate, to: observation.coordinate)
            .initialBearing
        return courseDifference(track, bearing) <= tolerance
    }

    private func runwayDifference(_ track: Bearing, runway: RunwayRecord) throws -> Double {
        let bearing = try engine.greatCirclePosition(from: runway.lowEnd, to: runway.highEnd)
            .initialBearing
        let reverse = try Bearing(degrees: bearing.degrees + 180)
        return min(courseDifference(track, bearing), courseDifference(track, reverse))
    }

    private func courseDifference(_ lhs: Bearing, _ rhs: Bearing) -> Double {
        let difference = abs(lhs.degrees - rhs.degrees).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }
}
