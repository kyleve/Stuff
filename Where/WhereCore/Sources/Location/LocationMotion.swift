import Foundation

/// Optional sensor measurements accompanying a GPS fix. Missing or invalid system
/// measurements stay absent; inferred travel speeds are never stored as sensor readings.
public struct LocationMotion: Hashable, Codable, Sendable {
    public struct Speed: Hashable, Codable, Sendable {
        public let metersPerSecond: Double
        public let accuracyMetersPerSecond: Double

        public init(metersPerSecond: Double, accuracyMetersPerSecond: Double) {
            self.metersPerSecond = metersPerSecond
            self.accuracyMetersPerSecond = accuracyMetersPerSecond
        }
    }

    public struct Altitude: Hashable, Codable, Sendable {
        public let meters: Double
        public let accuracyMeters: Double

        public init(meters: Double, accuracyMeters: Double) {
            self.meters = meters
            self.accuracyMeters = accuracyMeters
        }
    }

    public let speed: Speed?
    public let altitude: Altitude?

    public init(speed: Speed?, altitude: Altitude?) {
        self.speed = speed
        self.altitude = altitude
    }
}
