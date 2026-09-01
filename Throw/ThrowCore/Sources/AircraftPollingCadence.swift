import Foundation

/// A positive interval between aircraft polling attempts.
public struct AircraftPollingCadence: Hashable, Sendable {
    public let duration: Duration

    public init(duration: Duration) throws {
        guard duration > .zero else {
            throw AircraftPollingCadenceError.nonPositiveDuration
        }
        self.duration = duration
    }
}

public enum AircraftPollingCadenceError: Error, Equatable, Sendable {
    case nonPositiveDuration
}
