import Foundation

public struct FlightPrediction<Element: ProjectionMarkElement>: Hashable, Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let mark: ProjectionMark<Element>
    public let opacity: Double

    public init(mark: ProjectionMark<Element>, opacity: Double) {
        precondition((0 ... 1).contains(opacity))
        self.mark = mark
        self.opacity = opacity
    }

    public var description: String {
        "<FlightPrediction redacted>"
    }

    public var debugDescription: String {
        description
    }
}

/// Dead-reckons a successful observation until a later poll replaces it. A
/// retryable feed failure keeps predicting for 15 seconds, then fades for 15 seconds.
public enum FlightPredictor {
    public static let failureGracePeriod: TimeInterval = 15
    public static let failureFadeDuration: TimeInterval = 15
    static let turnPredictionDuration: TimeInterval = 12

    public static func prediction<Element: ProjectionMarkElement>(
        for mark: ProjectionMark<Element>,
        at date: Date,
    ) throws -> FlightPrediction<Element>? {
        guard let age = observationAge(
            positionObservedAt: mark.freshness.positionObservedAt,
            at: date,
        ) else {
            return nil
        }
        guard let opacity = availabilityOpacity(
            for: mark.freshness.availability,
            at: date,
        ) else { return nil }
        let predictedMark = try predictedMark(for: mark, observationAge: age)
        return FlightPrediction(mark: predictedMark, opacity: opacity)
    }

    static func predictedMark<Element: ProjectionMarkElement>(
        for mark: ProjectionMark<Element>,
        at date: Date,
    ) throws -> ProjectionMark<Element>? {
        guard let age = observationAge(
            positionObservedAt: mark.freshness.positionObservedAt,
            at: date,
        ) else {
            return nil
        }
        return try predictedMark(for: mark, observationAge: age)
    }

    private static func predictedMark<Element: ProjectionMarkElement>(
        for mark: ProjectionMark<Element>,
        observationAge: TimeInterval,
    ) throws -> ProjectionMark<Element> {
        let predictionAge = observationAge
        guard predictionAge > 0,
              case let .geodetic(anchor) = mark.anchor
        else {
            return mark
        }

        let coordinate: GeoCoordinate = if let transitMotion = mark.transitMotion {
            try transitCoordinate(
                for: transitMotion,
                at: mark.freshness.positionObservedAt.addingTimeInterval(observationAge),
            )
        } else if let track = mark.velocity?.groundTrack,
                  let speed = mark.velocity?.groundSpeedKnots
        {
            try predictedCoordinate(
                from: anchor.coordinate,
                track: track,
                speedKnots: speed,
                turnRateDegreesPerSecond: mark.velocity?.turnRateDegreesPerSecond,
                predictionAge: predictionAge,
            )
        } else {
            anchor.coordinate
        }
        let altitude: GeodeticAltitude = switch anchor.altitude {
            case .unavailable:
                .unavailable
            case let .available(current, quality):
                if let verticalRate = mark.velocity?.verticalRateFeetPerMinute {
                    try .available(
                        predictedAltitude(
                            current: current,
                            verticalRateFeetPerMinute: verticalRate,
                            predictionAge: predictionAge,
                        ),
                        quality: quality,
                    )
                } else {
                    anchor.altitude
                }
        }
        let predictedAnchor = GeodeticAnchor(
            coordinate: coordinate,
            altitude: altitude,
        )
        return ProjectionMark(
            element: mark.element,
            anchor: .geodetic(predictedAnchor),
            label: mark.label,
            prominence: mark.prominence,
            velocity: mark.velocity,
            transitMotion: mark.transitMotion,
            freshness: mark.freshness,
        )
    }

    private static func transitCoordinate(
        for motion: TransitProjectionMotion,
        at date: Date,
    ) throws -> GeoCoordinate {
        let duration = motion.endsAt.timeIntervalSince(motion.startsAt)
        let elapsed = date.timeIntervalSince(motion.startsAt)
        let progress = min(max(elapsed / duration, 0), 1)
        guard let first = motion.points.first, let last = motion.points.last else {
            throw TransitDataError.invalidSchedule
        }
        let totalDistance = last.distance - first.distance
        guard totalDistance > 0 else { return last.coordinate }
        let target = first.distance + totalDistance * progress
        guard let upperIndex = motion.points.firstIndex(where: { $0.distance >= target }) else {
            return last.coordinate
        }
        guard upperIndex > 0 else { return first.coordinate }
        let lower = motion.points[upperIndex - 1]
        let upper = motion.points[upperIndex]
        let span = upper.distance - lower.distance
        guard span > 0 else { return upper.coordinate }
        let segmentProgress = (target - lower.distance) / span
        var longitudeDelta = upper.coordinate.longitude - lower.coordinate.longitude
        if longitudeDelta > 180 { longitudeDelta -= 360 }
        if longitudeDelta < -180 { longitudeDelta += 360 }
        var longitude = lower.coordinate.longitude + longitudeDelta * segmentProgress
        if longitude > 180 { longitude -= 360 }
        if longitude < -180 { longitude += 360 }
        return try GeoCoordinate(
            latitude: lower.coordinate.latitude +
                (upper.coordinate.latitude - lower.coordinate.latitude) * segmentProgress,
            longitude: longitude,
        )
    }

    static func observationAge(positionObservedAt: Date, at date: Date) -> TimeInterval? {
        let age = date.timeIntervalSince(positionObservedAt)
        guard age.isFinite, age >= 0 else { return nil }
        return age
    }

    private static func availabilityOpacity(
        for availability: MarkAvailability,
        at date: Date,
    ) -> Double? {
        switch availability {
            case .current:
                1
            case let .retrying(since):
                failureOpacity(
                    since: since,
                    at: date,
                    gracePeriod: failureGracePeriod,
                    fadeDuration: failureFadeDuration,
                )
            case let .transitRetrying(since):
                failureOpacity(
                    since: since,
                    at: date,
                    gracePeriod: 90,
                    fadeDuration: 30,
                )
        }
    }

    private static func failureOpacity(
        since: Date,
        at date: Date,
        gracePeriod: TimeInterval,
        fadeDuration: TimeInterval,
    ) -> Double? {
        guard let age = observationAge(positionObservedAt: since, at: date) else { return nil }
        guard age < gracePeriod + fadeDuration else { return nil }
        guard age > gracePeriod else { return 1 }
        return 1 - (age - gracePeriod) / fadeDuration
    }

    private static func predictedAltitude(
        current: Altitude,
        verticalRateFeetPerMinute: Double,
        predictionAge: TimeInterval,
    ) throws -> Altitude {
        let predictedFeet = current.feet + verticalRateFeetPerMinute * predictionAge / 60
        guard predictedFeet.isNaN == false else { return current }
        let boundedFeet = min(
            max(predictedFeet, Altitude.allowedFeet.lowerBound),
            Altitude.allowedFeet.upperBound,
        )
        return try Altitude(feet: boundedFeet)
    }

    private static func destination(
        from origin: GeoCoordinate,
        bearing: Bearing,
        distanceNauticalMiles: Double,
    ) throws -> GeoCoordinate {
        let earthRadiusNauticalMiles = 3440.0695
        let angularDistance = distanceNauticalMiles / earthRadiusNauticalMiles
        let latitude1 = origin.latitude * .pi / 180
        let longitude1 = origin.longitude * .pi / 180
        let bearingRadians = bearing.degrees * .pi / 180

        let latitude2 = asin(
            sin(latitude1) * cos(angularDistance) +
                cos(latitude1) * sin(angularDistance) * cos(bearingRadians),
        )
        let longitude2 = longitude1 + atan2(
            sin(bearingRadians) * sin(angularDistance) * cos(latitude1),
            cos(angularDistance) - sin(latitude1) * sin(latitude2),
        )
        var longitudeDegrees = longitude2 * 180 / .pi
        longitudeDegrees = (longitudeDegrees + 540).truncatingRemainder(dividingBy: 360) - 180
        return try GeoCoordinate(
            latitude: latitude2 * 180 / .pi,
            longitude: longitudeDegrees,
        )
    }

    private static func predictedCoordinate(
        from origin: GeoCoordinate,
        track: Bearing,
        speedKnots: Double,
        turnRateDegreesPerSecond: Double?,
        predictionAge: TimeInterval,
    ) throws -> GeoCoordinate {
        guard let turnRateDegreesPerSecond,
              abs(turnRateDegreesPerSecond) >= 0.03
        else {
            return try destination(
                from: origin,
                bearing: track,
                distanceNauticalMiles: speedKnots * predictionAge / 3600,
            )
        }

        let turnDuration = min(predictionAge, turnPredictionDuration)
        let angularRate = turnRateDegreesPerSecond * .pi / 180
        let initialTrack = track.degrees * .pi / 180
        let finalTrack = initialTrack + angularRate * turnDuration
        let speedNauticalMilesPerSecond = speedKnots / 3600
        let north = speedNauticalMilesPerSecond / angularRate *
            (sin(finalTrack) - sin(initialTrack))
        let east = speedNauticalMilesPerSecond / angularRate *
            (cos(initialTrack) - cos(finalTrack))
        let arcDistance = hypot(east, north)
        let arcBearing = try Bearing(degrees: atan2(east, north) * 180 / .pi)
        let afterTurn = try destination(
            from: origin,
            bearing: arcBearing,
            distanceNauticalMiles: arcDistance,
        )
        let remainingAge = predictionAge - turnDuration
        guard remainingAge > 0 else { return afterTurn }
        return try destination(
            from: afterTurn,
            bearing: Bearing(degrees: finalTrack * 180 / .pi),
            distanceNauticalMiles: speedKnots * remainingAge / 3600,
        )
    }
}
