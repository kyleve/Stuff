import Foundation

/// A WGS84 latitude/longitude pair. Kept as a plain value type so the
/// pure model layer never has to link CoreLocation — the `Location/`
/// adapter converts from `CLLocation` at the boundary.
public struct Coordinate: Hashable, Codable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle (haversine) distance in meters to `other`.
    ///
    /// Uses a spherical-Earth model (mean radius 6 371 km), which is accurate
    /// to well within a percent at any distance the app cares about. Unlike
    /// `GeoPolygon`'s planar edge math — fine within one region's bounding box —
    /// this stays correct across continent-spanning gaps, so it's what the
    /// flight-day detector uses to turn consecutive fixes into a ground speed.
    public func distance(to other: Coordinate) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = (other.latitude - latitude) * .pi / 180
        let deltaLon = (other.longitude - longitude) * .pi / 180
        let haversine = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return 2 * earthRadiusMeters * asin(min(1, sqrt(haversine)))
    }
}

extension Collection<Coordinate> {
    /// Whether these coordinates form a drawable polygon ring. A ring
    /// needs at least three vertices to enclose an area; fewer can't be
    /// drawn or attributed against, so callers drop them.
    var isValidPolygonRing: Bool {
        count >= 3
    }
}
