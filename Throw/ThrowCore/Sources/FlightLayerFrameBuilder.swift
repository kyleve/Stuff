import Foundation

public struct FlightLayerFrameBuilder: Sendable {
    public init() {}

    public func frame(
        snapshot: AircraftSnapshot,
        observer: ObserverPosition,
        labelMode: FlightLabelMode,
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
                glyph: .aircraft(isGrounded: observation.airborneState == .ground),
                label: label(
                    for: observation,
                    observer: observer,
                    mode: labelMode,
                ),
                velocity: ProjectionVelocity(
                    groundTrack: observation.groundTrack,
                    groundSpeedKnots: observation.groundSpeedKnots,
                    verticalRateFeetPerMinute: observation.verticalRateFeetPerMinute,
                ),
                freshness: MarkFreshness(
                    positionObservedAt: observation.positionObservedAt,
                    fetchedAt: observation.fetchedAt,
                ),
            )
        }
        return LayerFrame(layerID: .flights, observedAt: snapshot.fetchedAt, marks: marks)
    }

    private func label(
        for observation: AircraftObservation,
        observer: ObserverPosition,
        mode: FlightLabelMode,
    ) throws -> ProjectionLabel? {
        switch mode {
            case .marksOnly:
                return nil
            case .callsigns:
                return observation.callsign.map { ProjectionLabel(primary: $0, secondary: nil) }
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

                if let callsign = observation.callsign {
                    return ProjectionLabel(
                        primary: callsign,
                        secondary: isNearby ? altitudeText : nil,
                    )
                }
                if isNearby, let altitudeText {
                    return ProjectionLabel(primary: altitudeText, secondary: nil)
                }
                return nil
        }
    }

    private static func altitudeText(_ altitude: Altitude) -> String {
        let rounded = Int((altitude.feet / 100).rounded()) * 100
        return Measurement(value: Double(rounded), unit: UnitLength.feet)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided))
    }
}
