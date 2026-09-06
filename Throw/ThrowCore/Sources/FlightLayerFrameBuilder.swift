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
        observations: [ResolvedAircraftObservation],
        observedAt: Date,
        providerRouteResults: [AircraftID: FlightRouteResult],
        observer: ObserverPosition,
        labelMode: FlightLabelMode,
        routeResults: [FlightCallsign: FlightRouteResult],
        availability: MarkAvailability,
    ) throws -> ProjectionLayerFrame<FlightsLayerKind> {
        var airportMarks: [AirportID: ProjectionMark<FlightsMarkElement>] = [:]
        var aircraftMarks: [ProjectionMark<FlightsMarkElement>] = []
        for resolvedObservation in observations {
            let observation = resolvedObservation.observation
            let motion = resolvedObservation.motion
            let callsign = observation.callsign.flatMap(FlightCallsign.init(rawValue:))
            let routeResult = providerRouteResults[observation.id]
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
            let anchor = GeodeticAnchor(
                coordinate: observation.coordinate,
                altitude: observation.skyAltitude,
            )
            try aircraftMarks.append(ProjectionMark(
                element: .aircraft(
                    id: observation.id,
                    glyph: visualClassifier.descriptor(
                        for: observation,
                        activity: activity,
                    ),
                ),
                anchor: .geodetic(anchor),
                label: label(
                    for: observation,
                    observer: observer,
                    mode: labelMode,
                    routeResult: routeResult,
                ),
                prominence: prominence,
                velocity: ProjectionVelocity(
                    horizontal: motion.horizontal,
                    verticalRateFeetPerMinute: motion.verticalRateFeetPerMinute,
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
                    element: .airport(AirportGlyphDescriptor(
                        airportID: airport.id,
                        code: code,
                        runwayBearing: runwayBearing,
                        certainty: activity.certainty ?? .inferred,
                    )),
                    anchor: .geodetic(GeodeticAnchor(
                        coordinate: airport.coordinate,
                        altitude: airport.elevation.map {
                            .available($0, quality: .geometric)
                        } ?? .unavailable,
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
            observedAt: observedAt,
            marks: aircraftMarks + airportMarks.sorted { $0.key.rawValue < $1.key.rawValue }
                .map(\.value),
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
                let altitudeText = observation.skyAltitude.value.map(Self.altitudeText)
                let isNearby: Bool
                if case let .available(altitude, quality) = observation.skyAltitude {
                    let position = try ProjectionEngine().horizontalPosition(
                        observer: observer,
                        target: GeodeticAnchor(
                            coordinate: observation.coordinate,
                            altitude: .available(altitude, quality: quality),
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
