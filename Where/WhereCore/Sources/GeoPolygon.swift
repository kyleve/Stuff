import Foundation

/// Axis-aligned latitude/longitude bounding box. Used as a cheap
/// pre-pass before running the polygon ray-cast: any coordinate
/// outside the box can't possibly be inside the underlying polygons,
/// so the more expensive `GeoPolygon.contains` check is skipped.
struct BoundingBox: Hashable {
    let minLatitude: Double
    let maxLatitude: Double
    let minLongitude: Double
    let maxLongitude: Double

    func contains(_ coordinate: Coordinate) -> Bool {
        coordinate.latitude >= minLatitude
            && coordinate.latitude <= maxLatitude
            && coordinate.longitude >= minLongitude
            && coordinate.longitude <= maxLongitude
    }

    /// Degenerate "contains nothing" box. Used only as a release-build
    /// fallback by callers (e.g. `RegionPolygons.init`) that
    /// `assertionFailure` on empty polygon sets but still need a
    /// concrete value to satisfy a non-optional property.
    static let empty = BoundingBox(
        minLatitude: .infinity,
        maxLatitude: -.infinity,
        minLongitude: .infinity,
        maxLongitude: -.infinity,
    )

    /// The smallest box that contains every vertex of every polygon in
    /// `polygons`. Returns `nil` only when every polygon is empty
    /// (which never happens with bundled GeoJSON; the optional is
    /// there so the helper is safe to use on arbitrary inputs too).
    static func enclosing(_ polygons: [GeoPolygon]) -> BoundingBox? {
        var minLat = Double.infinity
        var maxLat = -Double.infinity
        var minLng = Double.infinity
        var maxLng = -Double.infinity
        for polygon in polygons {
            for vertex in polygon.vertices {
                minLat = min(minLat, vertex.latitude)
                maxLat = max(maxLat, vertex.latitude)
                minLng = min(minLng, vertex.longitude)
                maxLng = max(maxLng, vertex.longitude)
            }
        }
        guard minLat.isFinite, maxLat.isFinite else { return nil }
        return BoundingBox(
            minLatitude: minLat,
            maxLatitude: maxLat,
            minLongitude: minLng,
            maxLongitude: maxLng,
        )
    }
}

/// A simple planar polygon used for offline region attribution.
///
/// `vertices` is the exterior ring. Holes aren't modeled because the bundled
/// simplified region polygons don't use them. Point-in-polygon is the
/// standard even-odd ray-cast on lat/lng treated as planar (x = longitude,
/// y = latitude). This is accurate enough at the scale of US states / EU /
/// Canada and is fully deterministic for snapshot tests.
struct GeoPolygon: Hashable {
    let vertices: [Coordinate]

    func contains(_ coordinate: Coordinate) -> Bool {
        let vertexCount = vertices.count
        guard vertexCount >= 3 else { return false }
        let pointX = coordinate.longitude
        let pointY = coordinate.latitude

        // Even-odd ray-casting: shoot a horizontal ray east from the
        // query point and count how many polygon edges it crosses. An
        // odd count means inside, even means outside. Each iteration
        // tests the edge between `vertices[previousIndex]` and
        // `vertices[currentIndex]`; the previous-index trick wraps the
        // final edge back to vertex 0 without a separate closing pass.
        var inside = false
        var previousIndex = vertexCount - 1
        for currentIndex in 0 ..< vertexCount {
            let currentX = vertices[currentIndex].longitude
            let currentY = vertices[currentIndex].latitude
            let previousX = vertices[previousIndex].longitude
            let previousY = vertices[previousIndex].latitude

            // The edge straddles the ray's latitude only if one
            // endpoint is above and the other is at-or-below `pointY`.
            if (currentY > pointY) != (previousY > pointY) {
                let t = (pointY - currentY) / (previousY - currentY)
                let intersectionX = currentX + t * (previousX - currentX)
                if pointX < intersectionX {
                    inside.toggle()
                }
            }
            previousIndex = currentIndex
        }
        return inside
    }
}
