import Foundation

public struct FlightLayerFrameBuilder: Sendable {
    private let visualClassifier: AircraftVisualClassifier
    private let activityClassifier: FlightActivityClassifier

    public init(
        visualClassifier: AircraftVisualClassifier,
        activityClassifier: FlightActivityClassifier,
    ) {
        self.visualClassifier = visualClassifier
        self.activityClassifier = activityClassifier
    }

    public func frame(
        snapshot: AircraftSnapshot,
        observer: ObserverPosition,
        labelMode: FlightLabelMode,
        routeResults: [FlightCallsign: FlightRouteResult],
        motions: [AircraftID: AircraftMotion],
        availability: MarkAvailability,
    ) throws -> ProjectionLayerFrame<FlightsLayerKind> {
        var airportMarks: [AirportID: ProjectionMark] = [:]
        var aircraftMarks: [ProjectionMark] = []
        for observation in snapshot.observations {
            guard let motion = motions[observation.id] else {
                preconditionFailure("Every observation must have resolved motion")
            }
            let callsign = observation.callsign.flatMap(FlightCallsign.init(rawValue:))
            let routeResult = snapshot.routeResultsByAircraft[observation.id]
                ?? callsign.flatMap { routeResults[$0] }
            let route = routeResult?.route
            let prominence: ProjectionProminence = if callsign == nil || routeResult ==
                .unavailable
            {
                .secondary
            } else {
                .primary
            }
            let activity = try activityClassifier.activity(
                for: observation,
                observer: observer,
                route: route,
                motion: motion,
            )
            let altitude = observation.preferredSkyAltitude
            let anchor = GeodeticAnchor(
                coordinate: observation.coordinate,
                altitude: altitude,
                altitudeQuality: observation.skyAltitudeQuality,
            )
            try aircraftMarks.append(ProjectionMark(
                id: observation.id.layerMarkID,
                anchor: .geodetic(anchor),
                glyph: .aircraft(visualClassifier.descriptor(
                    for: observation,
                    activity: activity,
                )),
                label: label(
                    for: observation,
                    observer: observer,
                    mode: labelMode,
                    routeResult: routeResult,
                ),
                prominence: prominence,
                velocity: ProjectionVelocity(
                    groundTrack: motion.groundTrack,
                    groundSpeedKnots: motion.groundSpeedKnots,
                    verticalRateFeetPerMinute: motion.verticalRateFeetPerMinute,
                    turnRateDegreesPerSecond: motion.turnRateDegreesPerSecond,
                    horizontalSource: motion.horizontalSource,
                ),
                freshness: MarkFreshness(
                    positionObservedAt: observation.positionObservedAt,
                    fetchedAt: observation.fetchedAt,
                    availability: availability,
                ),
            ))
            if let context = activity.airportContext {
                let airport = context.airport
                let runwayBearing: Bearing? = if let runway = airport.longestOpenRunway {
                    try ProjectionEngine().greatCirclePosition(
                        from: runway.lowEnd,
                        to: runway.highEnd,
                    ).initialBearing
                } else {
                    nil
                }
                let code = activity.certainty == .confirmed && labelMode != .marksOnly
                    ? airport.displayCode
                    : nil
                if let existing = airportMarks[airport.id],
                   case let .airport(existingDescriptor) = existing.glyph,
                   existingDescriptor.certainty == .confirmed,
                   activity.certainty == .inferred
                {
                    continue
                }
                airportMarks[airport.id] = ProjectionMark(
                    id: airport.id.layerMarkID,
                    anchor: .geodetic(GeodeticAnchor(
                        coordinate: airport.coordinate,
                        altitude: airport.elevation,
                        altitudeQuality: airport.elevation == nil ? .unavailable : .geometric,
                    )),
                    glyph: .airport(AirportGlyphDescriptor(
                        airportID: airport.id,
                        code: code,
                        runwayBearing: runwayBearing,
                        certainty: activity.certainty ?? .inferred,
                    )),
                    label: code.map {
                        ProjectionLabel(
                            primary: $0.rawValue,
                            primaryRole: .headline,
                            secondary: nil,
                        )
                    },
                    prominence: .primary,
                    velocity: nil,
                    freshness: MarkFreshness(
                        positionObservedAt: observation.positionObservedAt,
                        fetchedAt: observation.fetchedAt,
                        availability: availability,
                    ),
                )
            }
        }
        return ProjectionLayerFrame(
            observedAt: snapshot.fetchedAt,
            marks: aircraftMarks + airportMarks.values.sorted {
                $0.id.rawValue < $1.id.rawValue
            },
        )
    }

    private func label(
        for observation: AircraftObservation,
        observer: ObserverPosition,
        mode: FlightLabelMode,
        routeResult: FlightRouteResult?,
    ) throws -> ProjectionLabel? {
        let route = routeResult?.route
        switch mode {
            case .marksOnly:
                return nil
            case .callsigns:
                return label(route: route, callsign: observation.callsign)
            case .adaptive:
                let altitudeText = observation.preferredSkyAltitude.map(Self.altitudeText)
                let isNearby: Bool
                if let altitude = observation.preferredSkyAltitude {
                    let position = try ProjectionEngine().horizontalPosition(
                        observer: observer,
                        target: GeodeticAnchor(
                            coordinate: observation.coordinate,
                            altitude: altitude,
                            altitudeQuality: observation.skyAltitudeQuality,
                        ),
                    )
                    isNearby = (position?.slantRange.value ?? .infinity) <= 10
                } else {
                    isNearby = false
                }

                if observation.callsign != nil {
                    return label(route: route, callsign: observation.callsign)
                }
                if isNearby, let altitudeText {
                    return ProjectionLabel(
                        primary: altitudeText,
                        primaryRole: .headline,
                        secondary: nil,
                    )
                }
                return nil
        }
    }

    private func label(route: FlightRoute?, callsign: String?) -> ProjectionLabel? {
        guard let callsign else { return nil }
        guard let route else {
            return ProjectionLabel(
                primary: callsign,
                primaryRole: .detail,
                secondary: nil,
            )
        }
        return ProjectionLabel(
            primary: "\(route.origin.rawValue)→\(route.destination.rawValue)",
            primaryRole: .headline,
            secondary: callsign,
        )
    }

    private static func altitudeText(_ altitude: Altitude) -> String {
        let rounded = Int((altitude.feet / 100).rounded()) * 100
        return Measurement(value: Double(rounded), unit: UnitLength.feet)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided))
    }
}
