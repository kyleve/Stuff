import Foundation

public struct TransitLayerFrameBuilder: Sendable {
    public init() {}

    public func networkFrame(
        schedule: TransitSchedule,
    ) throws -> ProjectionLayerFrame<TransitNetworkLayerKind> {
        var emitted: Set<String> = []
        let lines = try schedule.tripPatterns.compactMap {
            pattern -> ProjectionPolyline<TransitNetworkLineStyle>? in
            let key = "\(pattern.routeID.rawValue)/\(pattern.shapeID)"
            guard emitted.insert(key).inserted,
                  let route = schedule.routes[pattern.routeID],
                  let shape = schedule.shapes[pattern.shapeID],
                  shape.count >= 2
            else { return nil }
            let coordinates = shape.map(\.coordinate)
            let latitudes = coordinates.map(\.latitude)
            let longitudes = coordinates.map(\.longitude)
            guard let south = latitudes.min(), let north = latitudes.max(),
                  let west = longitudes.min(), let east = longitudes.max()
            else { return nil }
            return try ProjectionPolyline(
                style: TransitNetworkLineStyle(
                    routeID: route.id,
                    color: route.color,
                ),
                detailLevel: .wide,
                bounds: GeographicBounds(
                    southLatitude: south,
                    westLongitude: west,
                    northLatitude: north,
                    eastLongitude: east,
                ),
                coordinates: coordinates,
            )
        }
        return ProjectionLayerFrame(observedAt: schedule.fetchedAt, lines: lines)
    }

    public func vehiclesFrame(
        estimates: [TransitVehicleEstimate],
        labelMode: TransitLabelMode,
        fetchedAt: Date,
        availability: MarkAvailability,
    ) -> ProjectionLayerFrame<TransitVehiclesLayerKind> {
        var marks: [ProjectionMark<TransitVehicleMarkElement>] = estimates.compactMap { estimate in
            guard let vehicleID = TransitVehicleID(rawValue: [
                estimate.run.id.agencyID.rawValue,
                estimate.run.id.partitionID.rawValue,
                estimate.run.id.serviceDate,
                estimate.run.id.stableRunValue,
            ].joined(separator: "/")) else { return nil }
            let label: ProjectionLabel? = switch labelMode {
                case .routeOnly:
                    nil
                case .destination:
                    estimate.destination.map {
                        ProjectionLabel(primary: $0.name, primaryRole: .detail, secondary: nil)
                    }
                case .nextStop:
                    ProjectionLabel(
                        primary: estimate.nextStop.name,
                        primaryRole: .detail,
                        secondary: nil,
                    )
            }
            return ProjectionMark(
                element: .vehicle(
                    id: vehicleID,
                    descriptor: TransitVehicleGlyphDescriptor(
                        routeLabel: estimate.route.shortName,
                        color: estimate.route.color,
                        confidence: estimate.confidence,
                    ),
                ),
                anchor: .geodetic(GeodeticAnchor(
                    coordinate: estimate.coordinate,
                    altitude: .unavailable,
                )),
                label: label,
                prominence: .primary,
                velocity: nil,
                transitMotion: estimate.motion,
                freshness: MarkFreshness(
                    positionObservedAt: estimate.run.observedAt,
                    fetchedAt: fetchedAt,
                    availability: availability,
                ),
            )
        }

        if labelMode != .routeOnly {
            var referenced: [TransitStopMarkID: (TransitStop, TransitColor)] = [:]
            for estimate in estimates {
                let stop: TransitStop?
                let context: String
                switch labelMode {
                    case .routeOnly:
                        continue
                    case .destination:
                        stop = estimate.destination
                        context = "destination"
                    case .nextStop:
                        stop = estimate.nextStop
                        context = "next-stop"
                }
                guard let stop else { continue }
                let id = TransitStopMarkID(stopID: stop.id.parentStationID, context: context)
                referenced[id] = (stop, estimate.route.color)
            }
            marks += referenced.map { id, value in
                ProjectionMark(
                    element: .stop(
                        id: id,
                        descriptor: TransitStopGlyphDescriptor(color: value.1),
                    ),
                    anchor: .geodetic(GeodeticAnchor(
                        coordinate: value.0.coordinate,
                        altitude: .unavailable,
                    )),
                    label: ProjectionLabel(
                        primary: value.0.name,
                        primaryRole: .detail,
                        secondary: nil,
                    ),
                    prominence: .secondary,
                    velocity: nil,
                    freshness: MarkFreshness(
                        positionObservedAt: fetchedAt,
                        fetchedAt: fetchedAt,
                        availability: availability,
                    ),
                )
            }
        }

        return ProjectionLayerFrame(observedAt: fetchedAt, marks: marks)
    }
}
