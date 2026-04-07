import Foundation

public struct TrackingWakeEvent: Equatable, Sendable {
    public let timestamp: Date
    public let reason: TrackingWakeReason
    public let latitude: Double
    public let longitude: Double
    public let horizontalAccuracy: Double?

    public init(
        timestamp: Date,
        reason: TrackingWakeReason,
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double? = nil,
    ) {
        self.timestamp = timestamp
        self.reason = reason
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
    }
}
