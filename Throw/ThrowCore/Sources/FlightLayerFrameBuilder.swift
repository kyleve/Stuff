import Foundation

public struct FlightLayerFrameBuilder: Sendable {
    private let visualClassifier: AircraftVisualClassifier

    public init(visualClassifier: AircraftVisualClassifier) {
        self.visualClassifier = visualClassifier
    }

    public func frame(
        snapshot: AircraftSnapshot,
        observer: ObserverPosition,
        labelMode: FlightLabelMode,
        routes: [FlightCallsign: FlightRoute],
        availability: MarkAvailability,
    ) throws -> LayerFrame {
        let marks = try snapshot.observations.map { observation in
            let altitude = observation.preferredSkyAltitude
            let anchor = GeodeticAnchor(
                coordinate: observation.coordinate,
                altitude: altitude,
                altitudeQuality: observation.skyAltitudeQuality,
            )
            return try ProjectionMark(
                id: observation.id.layerMarkID,
                anchor: .geodetic(anchor),
                glyph: .aircraft(visualClassifier.descriptor(for: observation)),
                label: label(
                    for: observation,
                    observer: observer,
                    mode: labelMode,
                    routes: routes,
                ),
                velocity: ProjectionVelocity(
                    groundTrack: observation.groundTrack,
                    groundSpeedKnots: observation.groundSpeedKnots,
                    verticalRateFeetPerMinute: observation.verticalRateFeetPerMinute,
                ),
                freshness: MarkFreshness(
                    positionObservedAt: observation.positionObservedAt,
                    fetchedAt: observation.fetchedAt,
                    availability: availability,
                ),
            )
        }
        return LayerFrame(
            layerID: .flights,
            observedAt: snapshot.fetchedAt,
            content: .marks(marks),
        )
    }

    private func label(
        for observation: AircraftObservation,
        observer: ObserverPosition,
        mode: FlightLabelMode,
        routes: [FlightCallsign: FlightRoute],
    ) throws -> ProjectionLabel? {
        let callsign = observation.callsign
            .flatMap(FlightCallsign.init(rawValue:))
        let route = callsign.flatMap { routes[$0] }
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
                    return ProjectionLabel(primary: altitudeText, secondary: nil)
                }
                return nil
        }
    }

    private func label(route: FlightRoute?, callsign: String?) -> ProjectionLabel? {
        guard let callsign else { return nil }
        guard let route else { return ProjectionLabel(primary: callsign, secondary: nil) }
        return ProjectionLabel(
            primary: "\(route.origin.rawValue) → \(route.destination.rawValue)",
            secondary: callsign,
        )
    }

    private static func altitudeText(_ altitude: Altitude) -> String {
        let rounded = Int((altitude.feet / 100).rounded()) * 100
        return Measurement(value: Double(rounded), unit: UnitLength.feet)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided))
    }
}
