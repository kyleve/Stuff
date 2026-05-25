import Foundation

/// A WGS84 latitude/longitude pair. Kept as a plain value type so that
/// `WhereCore` never has to link CoreLocation — callers in `WhereData`
/// convert from `CLLocation` at the boundary.
public struct Coordinate: Hashable, Codable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}
