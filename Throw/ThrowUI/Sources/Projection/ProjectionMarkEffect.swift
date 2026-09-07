import Foundation
import ThrowCore

struct ActivityCueEffect: Equatable {
    let previous: FlightActivity?
    let previousOpacity: Double
    let current: FlightActivity
    let currentOpacity: Double
}

enum AirportPulseDirection: Equatable {
    case inward
    case outward
}

struct AirportPulseEffect: Equatable {
    let direction: AirportPulseDirection
    let progress: Double
}

struct ProjectionMarkEffect: Equatable {
    let scale: Double
    let acquisitionProgress: Double?
    let activityCue: ActivityCueEffect?
    let airportPulse: AirportPulseEffect?

    static let identity = ProjectionMarkEffect(
        scale: 1,
        acquisitionProgress: nil,
        activityCue: nil,
        airportPulse: nil,
    )
}
