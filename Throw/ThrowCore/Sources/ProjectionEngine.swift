import Foundation

public struct ProjectionGeometry: Hashable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) throws {
        guard width.isFinite, height.isFinite else {
            throw ThrowValidationError.nonFiniteValue(field: "projectionGeometry")
        }
        guard width > 0, height > 0 else {
            throw ThrowValidationError.outOfRange(
                field: "projectionGeometry",
                closedRange: Double.leastNonzeroMagnitude ... Double.greatestFiniteMagnitude,
            )
        }
        self.width = width
        self.height = height
    }
}

public struct GreatCirclePosition: Hashable, Sendable {
    public let distance: NauticalMiles
    public let initialBearing: Bearing

    public init(distance: NauticalMiles, initialBearing: Bearing) {
        self.distance = distance
        self.initialBearing = initialBearing
    }
}

public struct HorizontalPosition: Hashable, Sendable {
    public let azimuth: Bearing
    public let elevation: ElevationAngle
    public let slantRange: NauticalMiles

    public init(azimuth: Bearing, elevation: ElevationAngle, slantRange: NauticalMiles) {
        self.azimuth = azimuth
        self.elevation = elevation
        self.slantRange = slantRange
    }
}

/// Pure geographic and WGS84 projection math. The returned points are already
/// calibrated and aspect-correct for the destination geometry.
public struct ProjectionEngine: Sendable {
    private static let earthMeanRadiusMeters = 6_371_008.8
    private static let wgs84SemiMajorAxisMeters = 6_378_137.0
    private static let wgs84Flattening = 1.0 / 298.257_223_563

    public init() {}

    public func frame(
        layerFrames: [LayerFrame],
        observer: ObserverPosition,
        viewport: ProjectionViewport,
        calibration: ProjectionCalibration,
        geometry: ProjectionGeometry,
        generatedAt: Date,
    ) throws -> ProjectionFrame {
        var projected: [ProjectedMark] = []
        for layerFrame in layerFrames {
            for mark in layerFrame.marks {
                guard let prediction = try FlightPredictor.prediction(for: mark, at: generatedAt)
                else {
                    continue
                }
                guard let radial = try radialPosition(
                    for: prediction.mark.anchor,
                    observer: observer,
                    viewport: viewport,
                    screenTopBearing: calibration.screenTopBearing,
                ) else {
                    continue
                }
                let point = calibratedPoint(
                    radial: radial,
                    calibration: calibration,
                    geometry: geometry,
                )
                let orientation = try apparentOrientation(
                    for: mark,
                    at: generatedAt,
                    observer: observer,
                    viewport: viewport,
                    calibration: calibration,
                    geometry: geometry,
                    currentPoint: point,
                )
                let altitudeIsApproximate: Bool = switch prediction.mark.anchor {
                    case let .geodetic(anchor):
                        anchor.altitudeQuality == .barometricApproximation
                    case .horizontal:
                        false
                }
                projected.append(
                    ProjectedMark(
                        id: prediction.mark.id,
                        point: point,
                        range: radial.range,
                        glyph: prediction.mark.glyph,
                        label: prediction.mark.label,
                        orientationDegrees: orientation,
                        opacity: prediction.opacity,
                        labelOpacity: 1,
                        altitudeIsApproximate: altitudeIsApproximate,
                    ),
                )
            }
        }
        return ProjectionFrame(mode: viewport.mode, generatedAt: generatedAt, marks: projected)
    }

    public func greatCirclePosition(
        from origin: GeoCoordinate,
        to destination: GeoCoordinate,
    ) throws -> GreatCirclePosition {
        let latitude1 = origin.latitude.radians
        let latitude2 = destination.latitude.radians
        let deltaLatitude = latitude2 - latitude1
        let deltaLongitude = normalizedRadians(destination.longitude.radians - origin.longitude
            .radians)

        let haversine = pow(sin(deltaLatitude / 2), 2) +
            cos(latitude1) * cos(latitude2) * pow(sin(deltaLongitude / 2), 2)
        let centralAngle = 2 * asin(sqrt(min(1, max(0, haversine))))
        let distance = try NauticalMiles(
            value: Self.earthMeanRadiusMeters * centralAngle / 1852,
        )

        let y = sin(deltaLongitude) * cos(latitude2)
        let x = cos(latitude1) * sin(latitude2) -
            sin(latitude1) * cos(latitude2) * cos(deltaLongitude)
        let bearingRadians = (abs(x) < 1e-15 && abs(y) < 1e-15) ? 0 : atan2(y, x)
        return try GreatCirclePosition(
            distance: distance,
            initialBearing: Bearing(degrees: bearingRadians.degrees),
        )
    }

    public func horizontalPosition(
        observer: ObserverPosition,
        target: GeodeticAnchor,
    ) throws -> HorizontalPosition? {
        guard let targetAltitude = target.altitude else { return nil }
        let observerECEF = ecef(
            coordinate: observer.coordinate,
            altitudeMeters: observer.altitude.meters,
        )
        let targetECEF = ecef(coordinate: target.coordinate, altitudeMeters: targetAltitude.meters)
        let deltaX = targetECEF.x - observerECEF.x
        let deltaY = targetECEF.y - observerECEF.y
        let deltaZ = targetECEF.z - observerECEF.z

        let latitude = observer.coordinate.latitude.radians
        let longitude = observer.coordinate.longitude.radians
        let east = -sin(longitude) * deltaX + cos(longitude) * deltaY
        let north = -sin(latitude) * cos(longitude) * deltaX -
            sin(latitude) * sin(longitude) * deltaY + cos(latitude) * deltaZ
        let up = cos(latitude) * cos(longitude) * deltaX +
            cos(latitude) * sin(longitude) * deltaY + sin(latitude) * deltaZ

        let horizontalRange = hypot(east, north)
        let slantRangeMeters = hypot(horizontalRange, up)
        let azimuthRadians = horizontalRange < 1e-9 ? 0 : atan2(east, north)
        let elevationRadians = atan2(up, horizontalRange)
        return try HorizontalPosition(
            azimuth: Bearing(degrees: azimuthRadians.degrees),
            elevation: ElevationAngle(degrees: elevationRadians.degrees),
            slantRange: NauticalMiles(value: slantRangeMeters / 1852),
        )
    }

    private func radialPosition(
        for anchor: ProjectionAnchor,
        observer: ObserverPosition,
        viewport: ProjectionViewport,
        screenTopBearing: Bearing,
    ) throws -> RadialPosition? {
        let horizontal: HorizontalAnchor
        let radius: Double
        let range: NauticalMiles?
        switch (viewport, anchor) {
            case let (.map(mapViewport), .geodetic(geodetic)):
                let geographic = try greatCirclePosition(
                    from: observer.coordinate,
                    to: geodetic.coordinate,
                )
                guard geographic.distance <= mapViewport.radius else { return nil }
                horizontal = try HorizontalAnchor(
                    azimuth: geographic.initialBearing,
                    elevation: ElevationAngle(degrees: 0),
                )
                radius = geographic.distance.value / mapViewport.radius.value
                range = geographic.distance
            case let (.trueSky(skyViewport), .geodetic(geodetic)):
                guard let position = try horizontalPosition(observer: observer, target: geodetic),
                      position.elevation.degrees >= skyViewport.minimumElevation.degrees
                else {
                    return nil
                }
                horizontal = HorizontalAnchor(
                    azimuth: position.azimuth,
                    elevation: position.elevation,
                )
                radius = (90 - position.elevation.degrees) /
                    (90 - skyViewport.minimumElevation.degrees)
                range = position.slantRange
            case let (.trueSky(skyViewport), .horizontal(value)):
                guard value.elevation.degrees >= skyViewport.minimumElevation.degrees else {
                    return nil
                }
                horizontal = value
                radius = (90 - value.elevation.degrees) /
                    (90 - skyViewport.minimumElevation.degrees)
                range = nil
            case (.map, .horizontal):
                return nil
        }

        let relativeBearing = (horizontal.azimuth.degrees - screenTopBearing.degrees).radians
        return RadialPosition(
            x: sin(relativeBearing) * radius,
            y: -cos(relativeBearing) * radius,
            range: range,
        )
    }

    private func calibratedPoint(
        radial: RadialPosition,
        calibration: ProjectionCalibration,
        geometry: ProjectionGeometry,
    ) -> ProjectionPoint {
        var x = radial.x
        var y = radial.y
        switch calibration.rotation {
            case .degrees0:
                break
            case .degrees90:
                (x, y) = (-y, x)
            case .degrees180:
                (x, y) = (-x, -y)
            case .degrees270:
                (x, y) = (y, -x)
        }
        if calibration.flipHorizontal { x = -x }
        if calibration.flipVertical { y = -y }

        let diameter = min(geometry.width, geometry.height) *
            (1 - 2 * calibration.safeInsetFraction)
        let pixelX = geometry.width / 2 + x * diameter / 2
        let pixelY = geometry.height / 2 + y * diameter / 2
        return ProjectionPoint(x: pixelX / geometry.width, y: pixelY / geometry.height)
    }

    private func apparentOrientation(
        for mark: ProjectionMark,
        at date: Date,
        observer: ObserverPosition,
        viewport: ProjectionViewport,
        calibration: ProjectionCalibration,
        geometry: ProjectionGeometry,
        currentPoint: ProjectionPoint,
    ) throws -> Double? {
        let hasHorizontalMotion = mark.velocity?.groundTrack != nil &&
            (mark.velocity?.groundSpeedKnots ?? 0) > 0
        let hasVerticalMotion = (mark.velocity?.verticalRateFeetPerMinute ?? 0) != 0
        guard hasHorizontalMotion || hasVerticalMotion,
              let next = try FlightPredictor.prediction(
                  for: mark,
                  at: date.addingTimeInterval(1),
              ),
              let nextRadial = try radialPosition(
                  for: next.mark.anchor,
                  observer: observer,
                  viewport: viewport,
                  screenTopBearing: calibration.screenTopBearing,
              )
        else {
            return nil
        }
        let nextPoint = calibratedPoint(
            radial: nextRadial,
            calibration: calibration,
            geometry: geometry,
        )
        let deltaX = (nextPoint.x - currentPoint.x) * geometry.width
        let deltaY = (nextPoint.y - currentPoint.y) * geometry.height
        guard hypot(deltaX, deltaY) > 1e-8 else { return nil }
        let radians = atan2(deltaX, -deltaY)
        let bearing = try Bearing(degrees: radians.degrees)
        return bearing.degrees
    }

    private func ecef(coordinate: GeoCoordinate, altitudeMeters: Double) -> CartesianPoint {
        let latitude = coordinate.latitude.radians
        let longitude = coordinate.longitude.radians
        let eccentricitySquared = Self.wgs84Flattening * (2 - Self.wgs84Flattening)
        let primeVerticalRadius = Self.wgs84SemiMajorAxisMeters /
            sqrt(1 - eccentricitySquared * pow(sin(latitude), 2))
        return CartesianPoint(
            x: (primeVerticalRadius + altitudeMeters) * cos(latitude) * cos(longitude),
            y: (primeVerticalRadius + altitudeMeters) * cos(latitude) * sin(longitude),
            z: (primeVerticalRadius * (1 - eccentricitySquared) + altitudeMeters) * sin(latitude),
        )
    }

    private func normalizedRadians(_ radians: Double) -> Double {
        var normalized = radians.truncatingRemainder(dividingBy: 2 * .pi)
        if normalized > .pi { normalized -= 2 * .pi }
        if normalized < -.pi { normalized += 2 * .pi }
        return normalized
    }
}

private struct RadialPosition {
    let x: Double
    let y: Double
    let range: NauticalMiles?
}

private struct CartesianPoint {
    let x: Double
    let y: Double
    let z: Double
}

extension Double {
    fileprivate var radians: Double {
        self * .pi / 180
    }

    fileprivate var degrees: Double {
        self * 180 / .pi
    }
}
