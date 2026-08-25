import Foundation

public struct FlightPrediction: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let mark: ProjectionMark
    public let opacity: Double

    public init(mark: ProjectionMark, opacity: Double) {
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

/// Dead-reckons aircraft for at most 15 seconds, then fades the last predicted
/// position until it expires at 30 seconds.
public enum FlightPredictor {
    public static let predictionLimit: TimeInterval = 15
    public static let expirationAge: TimeInterval = 30

    public static func prediction(
        for mark: ProjectionMark,
        at date: Date,
    ) throws -> FlightPrediction? {
        guard let age = observationAge(
            positionObservedAt: mark.freshness.positionObservedAt,
            at: date,
        ) else {
            return nil
        }
        guard age < expirationAge else { return nil }
        let opacity = age <= predictionLimit ? 1 :
            1 - (age - predictionLimit) / (expirationAge - predictionLimit)
        let predictionAge = min(age, predictionLimit)
        guard predictionAge > 0,
              case let .geodetic(anchor) = mark.anchor
        else {
            return FlightPrediction(mark: mark, opacity: opacity)
        }

        let coordinate: GeoCoordinate = if let track = mark.velocity?.groundTrack,
                                           let speed = mark.velocity?.groundSpeedKnots
        {
            try destination(
                from: anchor.coordinate,
                bearing: track,
                distanceNauticalMiles: speed * predictionAge / 3600,
            )
        } else {
            anchor.coordinate
        }
        let altitude: Altitude? = if let current = anchor.altitude,
                                     let verticalRate = mark.velocity?.verticalRateFeetPerMinute
        {
            try predictedAltitude(
                current: current,
                verticalRateFeetPerMinute: verticalRate,
                predictionAge: predictionAge,
            )
        } else {
            anchor.altitude
        }
        let predictedAnchor = GeodeticAnchor(
            coordinate: coordinate,
            altitude: altitude,
            altitudeQuality: anchor.altitudeQuality,
        )
        let predictedMark = ProjectionMark(
            id: mark.id,
            anchor: .geodetic(predictedAnchor),
            glyph: mark.glyph,
            label: mark.label,
            velocity: mark.velocity,
            freshness: mark.freshness,
        )
        return FlightPrediction(mark: predictedMark, opacity: opacity)
    }

    static func observationAge(positionObservedAt: Date, at date: Date) -> TimeInterval? {
        let age = date.timeIntervalSince(positionObservedAt)
        guard age.isFinite, age >= 0 else { return nil }
        return age
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
}
