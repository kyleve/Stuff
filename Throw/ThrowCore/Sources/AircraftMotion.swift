import Foundation

/// Identifies where a provider-neutral horizontal-motion estimate came from.
public enum AircraftHorizontalMotionSource: String, Hashable, Sendable {
    case provider
    case positionDerived = "position-derived"
}

/// A validated horizontal-motion value that can drive position prediction.
public struct AvailableAircraftHorizontalMotion: Hashable, Sendable {
    public let track: Bearing
    public let speedKnots: Double
    public let turnRateDegreesPerSecond: Double?
    public let source: AircraftHorizontalMotionSource

    public init(
        track: Bearing,
        speedKnots: Double,
        turnRateDegreesPerSecond: Double?,
        source: AircraftHorizontalMotionSource,
    ) throws {
        guard speedKnots.isFinite, (0 ... 2000).contains(speedKnots) else {
            throw ThrowValidationError.outOfRange(
                field: "groundSpeed",
                closedRange: 0 ... 2000,
            )
        }
        if let turnRateDegreesPerSecond {
            guard turnRateDegreesPerSecond.isFinite else {
                throw ThrowValidationError.nonFiniteValue(field: "turnRate")
            }
            guard (-3 ... 3).contains(turnRateDegreesPerSecond) else {
                throw ThrowValidationError.outOfRange(
                    field: "turnRate",
                    closedRange: -3 ... 3,
                )
            }
        }
        self.track = track
        self.speedKnots = speedKnots
        self.turnRateDegreesPerSecond = turnRateDegreesPerSecond
        self.source = source
    }
}

/// Horizontal motion is either unavailable or a complete validated value.
public enum AircraftHorizontalMotion: Hashable, Sendable {
    case unavailable(orientation: Bearing?)
    case available(AvailableAircraftHorizontalMotion)

    public var availableValue: AvailableAircraftHorizontalMotion? {
        if case let .available(value) = self { value } else { nil }
    }

    public var orientation: Bearing? {
        switch self {
            case let .unavailable(orientation): orientation
            case let .available(value): value.track
        }
    }
}

/// The motion Throw uses for prediction after validating provider values and
/// optionally reconciling them with consecutive observed positions.
public struct AircraftMotion: Hashable, Sendable {
    public let horizontal: AircraftHorizontalMotion
    public let verticalRateFeetPerMinute: Double?

    public init(
        horizontal: AircraftHorizontalMotion,
        verticalRateFeetPerMinute: Double?,
    ) throws {
        if let verticalRateFeetPerMinute {
            guard verticalRateFeetPerMinute.isFinite else {
                throw ThrowValidationError.nonFiniteValue(field: "verticalRate")
            }
        }
        self.horizontal = horizontal
        self.verticalRateFeetPerMinute = verticalRateFeetPerMinute
    }

    public var groundTrack: Bearing? {
        horizontal.orientation
    }

    public var groundSpeedKnots: Double? {
        horizontal.availableValue?.speedKnots
    }

    public var turnRateDegreesPerSecond: Double? {
        horizontal.availableValue?.turnRateDegreesPerSecond
    }

    public var horizontalSource: AircraftHorizontalMotionSource? {
        horizontal.availableValue?.source
    }

    public static func reported(by observation: AircraftObservation) -> AircraftMotion {
        let horizontal: AircraftHorizontalMotion
        if let track = observation.groundTrack,
           let speedKnots = observation.groundSpeedKnots
        {
            do {
                horizontal = try .available(
                    AvailableAircraftHorizontalMotion(
                        track: track,
                        speedKnots: speedKnots,
                        turnRateDegreesPerSecond: nil,
                        source: .provider,
                    ),
                )
            } catch {
                preconditionFailure("A validated observation must contain valid motion: \(error)")
            }
        } else {
            horizontal = .unavailable(orientation: observation.groundTrack)
        }
        do {
            return try AircraftMotion(
                horizontal: horizontal,
                verticalRateFeetPerMinute: observation.verticalRateFeetPerMinute,
            )
        } catch {
            preconditionFailure("A validated observation must contain valid motion: \(error)")
        }
    }
}
