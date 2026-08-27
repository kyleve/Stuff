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

    #if DEBUG
        public func frame(
            layerFrames: [LayerFrame],
            geography: ProjectedGeography?,
            observer: ObserverPosition,
            viewport: ProjectionViewport,
            calibration: ProjectionCalibration,
            geometry: ProjectionGeometry,
            generatedAt: Date,
        ) throws -> ProjectionFrame {
            try frame(
                layerFrames: layerFrames,
                geography: geography,
                observer: observer,
                mapCenter: observer.coordinate,
                viewport: viewport,
                calibration: calibration,
                geometry: geometry,
                generatedAt: generatedAt,
            )
        }

        public func frame(
            layerFrames: [LayerFrame],
            geography: ProjectedGeography?,
            observer: ObserverPosition,
            mapCenter: GeoCoordinate,
            viewport: ProjectionViewport,
            calibration: ProjectionCalibration,
            geometry: ProjectionGeometry,
            generatedAt: Date,
        ) throws -> ProjectionFrame {
            let zOrders = Dictionary(
                uniqueKeysWithValues: LayerCatalog.standard.descriptors.map { ($0.id, $0.zOrder) },
            )
            let lineLayers: [ProjectedLayer] = geography.map {
                [
                    ProjectedLayer(
                        id: .geography,
                        zOrder: zOrders[.geography] ?? 0,
                        opacity: 1,
                        content: .lines($0),
                    ),
                ]
            } ?? []
            return try frameUnchecked(
                experienceID: .airAndSpace,
                layerFrames: layerFrames,
                projectedLineLayers: lineLayers,
                layerZOrders: zOrders,
                observer: observer,
                mapCenter: mapCenter,
                viewport: viewport,
                calibration: calibration,
                geometry: geometry,
                generatedAt: generatedAt,
            )
        }

        public func frameForTesting(
            experienceID: ProjectionExperienceID,
            layerFrames: [LayerFrame],
            projectedLineLayers: [ProjectedLayer],
            layerZOrders: [LayerID: Int],
            observer: ObserverPosition,
            mapCenter: GeoCoordinate,
            viewport: ProjectionViewport,
            calibration: ProjectionCalibration,
            geometry: ProjectionGeometry,
            generatedAt: Date,
        ) throws -> ProjectionFrame {
            try frameUnchecked(
                experienceID: experienceID,
                layerFrames: layerFrames,
                projectedLineLayers: projectedLineLayers,
                layerZOrders: layerZOrders,
                observer: observer,
                mapCenter: mapCenter,
                viewport: viewport,
                calibration: calibration,
                geometry: geometry,
                generatedAt: generatedAt,
            )
        }
    #endif

    public func frame(
        input: ProjectionExperienceInput,
        projectedLineLayers: [ProjectedLayer],
        layerZOrders: [LayerID: Int],
        observer: ObserverPosition,
        mapCenter: GeoCoordinate,
        calibration: ProjectionCalibration,
        geometry: ProjectionGeometry,
        generatedAt: Date,
    ) throws -> ProjectionFrame {
        try frameUnchecked(
            experienceID: input.experienceFrame.experienceID,
            layerFrames: input.experienceFrame.layers,
            projectedLineLayers: projectedLineLayers,
            layerZOrders: layerZOrders,
            observer: observer,
            mapCenter: mapCenter,
            viewport: input.viewport,
            calibration: calibration,
            geometry: geometry,
            generatedAt: generatedAt,
        )
    }

    private func frameUnchecked(
        experienceID: ProjectionExperienceID,
        layerFrames: [LayerFrame],
        projectedLineLayers: [ProjectedLayer],
        layerZOrders: [LayerID: Int],
        observer: ObserverPosition,
        mapCenter: GeoCoordinate,
        viewport: ProjectionViewport,
        calibration: ProjectionCalibration,
        geometry: ProjectionGeometry,
        generatedAt: Date,
    ) throws -> ProjectionFrame {
        try Task.checkCancellation()
        let projectionObserver = switch viewport {
            case .map:
                ObserverPosition(coordinate: mapCenter, altitude: observer.altitude)
            case .trueSky:
                observer
        }
        var projectedLayers = projectedLineLayers
        for layerFrame in layerFrames {
            var projected: [ProjectedMark] = []
            for (markIndex, mark) in layerFrame.marks.enumerated() {
                if markIndex.isMultiple(of: 64) {
                    try Task.checkCancellation()
                }
                if case .airport = mark.glyph, viewport.mode != .map { continue }
                guard let prediction = try FlightPredictor.prediction(for: mark, at: generatedAt)
                else {
                    continue
                }
                guard let radial = try radialPosition(
                    for: prediction.mark.anchor,
                    observer: projectionObserver,
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
                let orientation = switch mark.glyph {
                    case let .airport(descriptor): try projectedOrientation(
                            bearing: descriptor.runwayBearing,
                            anchor: prediction.mark.anchor,
                            observer: projectionObserver,
                            viewport: viewport,
                            calibration: calibration,
                            geometry: geometry,
                            currentPoint: point,
                        )
                    case .aircraft, .star, .satellite: try apparentOrientation(
                            for: mark,
                            at: generatedAt,
                            observer: projectionObserver,
                            viewport: viewport,
                            calibration: calibration,
                            geometry: geometry,
                            currentPoint: point,
                        )
                }
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
                        secondaryProminence: prediction.mark.prominence == .secondary ? 1 : 0,
                        orientationDegrees: orientation,
                        opacity: prediction.opacity,
                        labelOpacity: 1,
                        altitudeIsApproximate: altitudeIsApproximate,
                    ),
                )
            }
            if case .marks = layerFrame.content {
                projectedLayers.append(
                    ProjectedLayer(
                        id: layerFrame.layerID,
                        zOrder: layerZOrders[layerFrame.layerID] ?? 0,
                        opacity: 1,
                        content: .marks(projected),
                    ),
                )
            }
        }
        return ProjectionFrame(
            experienceID: experienceID,
            mode: viewport.mode,
            generatedAt: generatedAt,
            layers: projectedLayers,
        )
    }

    /// Projects and clips static geographic or network lines for a Map viewport. Callers
    /// can cache the result until the Map center, viewport, or calibration changes.
    public func lineSegments(
        lines: [ProjectionPolyline],
        mapCenter: GeoCoordinate,
        viewport: ProjectionViewport,
        calibration: ProjectionCalibration,
        geometry: ProjectionGeometry,
    ) throws -> [ProjectedGeographySegment] {
        try Task.checkCancellation()
        guard case let .map(mapViewport) = viewport else { return [] }
        var segments: [ProjectedGeographySegment] = []
        for (lineIndex, line) in lines.enumerated() {
            if lineIndex.isMultiple(of: 64) {
                try Task.checkCancellation()
            }
            guard line.detailLevel.includes(mapRadius: mapViewport.radius) else {
                continue
            }
            guard line.bounds.mayIntersect(
                observer: mapCenter,
                radius: mapViewport.radius,
            ) else {
                continue
            }
            var previousIndex = line.coordinates.startIndex
            var currentIndex = line.coordinates.index(after: previousIndex)
            var previousProjectedEnd: RadialPosition?
            var segmentIndex = 0
            while currentIndex != line.coordinates.endIndex {
                if segmentIndex.isMultiple(of: 256) {
                    try Task.checkCancellation()
                }
                let start = try mapRadialPosition(
                    for: line.coordinates[previousIndex],
                    center: mapCenter,
                    viewport: mapViewport,
                    screenTopBearing: calibration.screenTopBearing,
                )
                let end = try mapRadialPosition(
                    for: line.coordinates[currentIndex],
                    center: mapCenter,
                    viewport: mapViewport,
                    screenTopBearing: calibration.screenTopBearing,
                )
                if let clipped = clippedToUnitCircle(start: start, end: end) {
                    let startsNewSubpath = previousProjectedEnd.map {
                        radialPointsMatch($0, clipped.start) == false
                    } ?? true
                    segments.append(
                        ProjectedLineSegment(
                            styleID: line.styleID,
                            start: calibratedPoint(
                                radial: clipped.start,
                                calibration: calibration,
                                geometry: geometry,
                            ),
                            end: calibratedPoint(
                                radial: clipped.end,
                                calibration: calibration,
                                geometry: geometry,
                            ),
                            startsNewSubpath: startsNewSubpath,
                        ),
                    )
                    previousProjectedEnd = clipped.end
                } else {
                    previousProjectedEnd = nil
                }
                previousIndex = currentIndex
                line.coordinates.formIndex(after: &currentIndex)
                segmentIndex += 1
            }
        }
        return segments
    }

    public func geographySegments(
        lines: [GeographicPolyline],
        mapCenter: GeoCoordinate,
        viewport: ProjectionViewport,
        calibration: ProjectionCalibration,
        geometry: ProjectionGeometry,
    ) throws -> [ProjectedGeographySegment] {
        try lineSegments(
            lines: lines,
            mapCenter: mapCenter,
            viewport: viewport,
            calibration: calibration,
            geometry: geometry,
        )
    }

    public func geographySegments(
        lines: [GeographicPolyline],
        observer: ObserverPosition,
        viewport: ProjectionViewport,
        calibration: ProjectionCalibration,
        geometry: ProjectionGeometry,
    ) throws -> [ProjectedGeographySegment] {
        try geographySegments(
            lines: lines,
            mapCenter: observer.coordinate,
            viewport: viewport,
            calibration: calibration,
            geometry: geometry,
        )
    }

    private func radialPointsMatch(_ lhs: RadialPosition, _ rhs: RadialPosition) -> Bool {
        abs(lhs.x - rhs.x) <= 1e-12 && abs(lhs.y - rhs.y) <= 1e-12
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

    public func destination(
        from origin: GeoCoordinate,
        bearing: Bearing,
        distance: NauticalMiles,
    ) throws -> GeoCoordinate {
        try destination(
            from: origin,
            bearing: bearing,
            distanceNauticalMiles: distance.value,
        )
    }

    public func mapPoint(
        for coordinate: GeoCoordinate,
        center: GeoCoordinate,
        viewport: MapViewport,
        calibration: ProjectionCalibration,
        geometry: ProjectionGeometry,
    ) throws -> ProjectionPoint? {
        let radial = try mapRadialPosition(
            for: coordinate,
            center: center,
            viewport: viewport,
            screenTopBearing: calibration.screenTopBearing,
        )
        guard let range = radial.range, range <= viewport.radius else { return nil }
        return calibratedPoint(radial: radial, calibration: calibration, geometry: geometry)
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
                let radial = try mapRadialPosition(
                    for: geodetic.coordinate,
                    center: observer.coordinate,
                    viewport: mapViewport,
                    screenTopBearing: screenTopBearing,
                )
                guard let range = radial.range, range <= mapViewport.radius else { return nil }
                return radial
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

    private func mapRadialPosition(
        for coordinate: GeoCoordinate,
        center: GeoCoordinate,
        viewport: MapViewport,
        screenTopBearing: Bearing,
    ) throws -> RadialPosition {
        let geographic = try greatCirclePosition(
            from: center,
            to: coordinate,
        )
        let relativeBearing = (
            geographic.initialBearing.degrees - screenTopBearing.degrees,
        ).radians
        let radius = geographic.distance.value / viewport.radius.value
        return RadialPosition(
            x: sin(relativeBearing) * radius,
            y: -cos(relativeBearing) * radius,
            range: geographic.distance,
        )
    }

    private func clippedToUnitCircle(
        start: RadialPosition,
        end: RadialPosition,
    ) -> RadialSegment? {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let coefficientA = deltaX * deltaX + deltaY * deltaY
        guard coefficientA > 1e-16 else { return nil }
        let coefficientB = 2 * (start.x * deltaX + start.y * deltaY)
        let coefficientC = start.x * start.x + start.y * start.y - 1
        let discriminant = coefficientB * coefficientB - 4 * coefficientA * coefficientC
        guard discriminant >= 0 else { return nil }

        let root = sqrt(discriminant)
        let firstIntersection = (-coefficientB - root) / (2 * coefficientA)
        let secondIntersection = (-coefficientB + root) / (2 * coefficientA)
        let lower = max(0, min(firstIntersection, secondIntersection))
        let upper = min(1, max(firstIntersection, secondIntersection))
        guard upper - lower > 1e-12 else { return nil }

        return RadialSegment(
            start: RadialPosition(
                x: start.x + deltaX * lower,
                y: start.y + deltaY * lower,
                range: nil,
            ),
            end: RadialPosition(
                x: start.x + deltaX * upper,
                y: start.y + deltaY * upper,
                range: nil,
            ),
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
        guard hasHorizontalMotion || hasVerticalMotion else { return nil }
        guard FlightPredictor.observationAge(
            positionObservedAt: mark.freshness.positionObservedAt,
            at: date,
        ) != nil else { return nil }
        let comparisonDate = date.addingTimeInterval(1)
        guard let comparisonMark = try FlightPredictor.predictedMark(
            for: mark,
            at: comparisonDate,
        ),
            let comparisonRadial = try radialPosition(
                for: comparisonMark.anchor,
                observer: observer,
                viewport: viewport,
                screenTopBearing: calibration.screenTopBearing,
            )
        else {
            return nil
        }
        let comparisonPoint = calibratedPoint(
            radial: comparisonRadial,
            calibration: calibration,
            geometry: geometry,
        )
        let deltaX = (comparisonPoint.x - currentPoint.x) * geometry.width
        let deltaY = (comparisonPoint.y - currentPoint.y) * geometry.height
        guard hypot(deltaX, deltaY) > 1e-8 else { return nil }
        let radians = atan2(deltaX, -deltaY)
        let bearing = try Bearing(degrees: radians.degrees)
        return bearing.degrees
    }

    private func projectedOrientation(
        bearing: Bearing?,
        anchor: ProjectionAnchor,
        observer: ObserverPosition,
        viewport: ProjectionViewport,
        calibration: ProjectionCalibration,
        geometry: ProjectionGeometry,
        currentPoint: ProjectionPoint,
    ) throws -> Double? {
        guard let bearing, case let .geodetic(anchor) = anchor else { return nil }
        let comparisonCoordinate = try destination(
            from: anchor.coordinate,
            bearing: bearing,
            distanceNauticalMiles: 0.25,
        )
        let comparisonAnchor = GeodeticAnchor(
            coordinate: comparisonCoordinate,
            altitude: anchor.altitude,
            altitudeQuality: anchor.altitudeQuality,
        )
        guard let radial = try radialPosition(
            for: .geodetic(comparisonAnchor),
            observer: observer,
            viewport: viewport,
            screenTopBearing: calibration.screenTopBearing,
        ) else { return nil }
        let comparisonPoint = calibratedPoint(
            radial: radial,
            calibration: calibration,
            geometry: geometry,
        )
        let deltaX = (comparisonPoint.x - currentPoint.x) * geometry.width
        let deltaY = (comparisonPoint.y - currentPoint.y) * geometry.height
        guard hypot(deltaX, deltaY) > 1e-8 else { return nil }
        return try Bearing(degrees: atan2(deltaX, -deltaY).degrees).degrees
    }

    private func destination(
        from origin: GeoCoordinate,
        bearing: Bearing,
        distanceNauticalMiles: Double,
    ) throws -> GeoCoordinate {
        let angularDistance = distanceNauticalMiles / 3440.0695
        let latitude = origin.latitude.radians
        let longitude = origin.longitude.radians
        let direction = bearing.degrees.radians
        let resultLatitude = asin(
            sin(latitude) * cos(angularDistance) +
                cos(latitude) * sin(angularDistance) * cos(direction),
        )
        let resultLongitude = longitude + atan2(
            sin(direction) * sin(angularDistance) * cos(latitude),
            cos(angularDistance) - sin(latitude) * sin(resultLatitude),
        )
        var longitudeDegrees = resultLongitude.degrees
        longitudeDegrees = (longitudeDegrees + 540).truncatingRemainder(dividingBy: 360) - 180
        return try GeoCoordinate(latitude: resultLatitude.degrees, longitude: longitudeDegrees)
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

private struct RadialSegment {
    let start: RadialPosition
    let end: RadialPosition
}

extension GeographicBounds {
    fileprivate func mayIntersect(observer: GeoCoordinate, radius: NauticalMiles) -> Bool {
        let earthMeanRadiusNauticalMiles = 6_371_008.8 / 1852
        let angularRadius = radius.value / earthMeanRadiusNauticalMiles
        let latitudeDelta = angularRadius.degrees
        let querySouth = max(-90, observer.latitude - latitudeDelta)
        let queryNorth = min(90, observer.latitude + latitudeDelta)
        guard northLatitude >= querySouth, southLatitude <= queryNorth else { return false }

        let observerLatitude = observer.latitude.radians
        guard abs(observerLatitude) + angularRadius < .pi / 2 else { return true }
        let longitudeDelta = asin(
            min(1, sin(angularRadius) / cos(observerLatitude)),
        ).degrees
        let queryWest = observer.longitude - longitudeDelta
        let queryEast = observer.longitude + longitudeDelta
        if queryWest < -180 {
            return eastLongitude >= queryWest + 360 || westLongitude <= queryEast
        }
        if queryEast > 180 {
            return eastLongitude >= queryWest || westLongitude <= queryEast - 360
        }
        return eastLongitude >= queryWest && westLongitude <= queryEast
    }
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
