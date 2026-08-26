import Foundation

/// Identifies whether Throw can project horizontal motion and where that
/// provider-neutral estimate came from.
public enum AircraftHorizontalMotionSource: String, Hashable, Sendable {
    case unavailable
    case provider
    case positionDerived = "position-derived"
}

/// The motion Throw uses for prediction after validating provider values and
/// optionally reconciling them with consecutive observed positions.
public struct AircraftMotion: Hashable, Sendable {
    public let groundTrack: Bearing?
    public let groundSpeedKnots: Double?
    public let verticalRateFeetPerMinute: Double?
    public let turnRateDegreesPerSecond: Double?
    public let horizontalSource: AircraftHorizontalMotionSource

    public init(
        groundTrack: Bearing?,
        groundSpeedKnots: Double?,
        verticalRateFeetPerMinute: Double?,
        turnRateDegreesPerSecond: Double?,
        horizontalSource: AircraftHorizontalMotionSource,
    ) throws {
        if let groundSpeedKnots {
            guard groundSpeedKnots.isFinite, (0 ... 2000).contains(groundSpeedKnots) else {
                throw ThrowValidationError.outOfRange(
                    field: "groundSpeed",
                    closedRange: 0 ... 2000,
                )
            }
        }
        if let verticalRateFeetPerMinute {
            guard verticalRateFeetPerMinute.isFinite else {
                throw ThrowValidationError.nonFiniteValue(field: "verticalRate")
            }
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
        precondition(
            horizontalSource == .unavailable ||
                (groundTrack != nil && groundSpeedKnots != nil),
            "Available horizontal motion requires both track and speed",
        )
        precondition(
            turnRateDegreesPerSecond == nil ||
                (groundTrack != nil && groundSpeedKnots != nil),
            "Turn-rate prediction requires horizontal motion",
        )
        self.groundTrack = groundTrack
        self.groundSpeedKnots = groundSpeedKnots
        self.verticalRateFeetPerMinute = verticalRateFeetPerMinute
        self.turnRateDegreesPerSecond = turnRateDegreesPerSecond
        self.horizontalSource = horizontalSource
    }

    public static func reported(by observation: AircraftObservation) -> AircraftMotion {
        let source: AircraftHorizontalMotionSource = if observation.groundTrack != nil,
                                                        observation.groundSpeedKnots != nil
        {
            .provider
        } else {
            .unavailable
        }
        do {
            return try AircraftMotion(
                groundTrack: observation.groundTrack,
                groundSpeedKnots: observation.groundSpeedKnots,
                verticalRateFeetPerMinute: observation.verticalRateFeetPerMinute,
                turnRateDegreesPerSecond: nil,
                horizontalSource: source,
            )
        } catch {
            preconditionFailure("A validated observation must contain valid motion: \(error)")
        }
    }
}
