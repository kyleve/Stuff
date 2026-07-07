import Foundation

/// Axis-aligned latitude/longitude bounding box. Used as a cheap
/// pre-pass before running the polygon ray-cast: any coordinate
/// outside the box can't possibly be inside the underlying polygons,
/// so the more expensive `GeoPolygon.contains` check is skipped.
///
/// Public so the developer region-map viewer can frame its camera's
/// latitude from the same min/max math (via `enclosing(_:)`); longitude
/// is framed separately with `LongitudeSpan` because it can wrap the
/// antimeridian. RegionKit stays UI-free, so the MapKit conversion
/// happens in the UI layer.
public struct BoundingBox: Hashable, Sendable {
    public let minLatitude: Double
    public let maxLatitude: Double
    public let minLongitude: Double
    public let maxLongitude: Double

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
        enclosing(polygons.lazy.flatMap(\.vertices))
    }

    /// The smallest box that contains every coordinate in `coordinates`,
    /// or `nil` when the sequence is empty. The shared core both the
    /// `[GeoPolygon]` overload and the region-map viewer's camera
    /// framing build on, so the min/max sweep lives in one place.
    static func enclosing(_ coordinates: some Sequence<Coordinate>) -> BoundingBox? {
        var minLat = Double.infinity
        var maxLat = -Double.infinity
        var minLng = Double.infinity
        var maxLng = -Double.infinity
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLng = min(minLng, coordinate.longitude)
            maxLng = max(maxLng, coordinate.longitude)
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
        guard vertices.isValidPolygonRing else { return false }
        let vertexCount = vertices.count
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

    /// Smallest distance in meters from `coordinate` to this polygon's edge ring.
    func distanceToBoundary(from coordinate: Coordinate) -> Double {
        guard vertices.count >= 2 else { return .infinity }
        let metersPerLatitude = 111_320.0
        let metersPerLongitude = 111_320.0 * cos(coordinate.latitude * .pi / 180)
        func project(_ c: Coordinate) -> PlanarPoint {
            PlanarPoint(
                x: (c.longitude - coordinate.longitude) * metersPerLongitude,
                y: (c.latitude - coordinate.latitude) * metersPerLatitude,
            )
        }
        let origin = PlanarPoint(x: 0, y: 0)
        var best = Double.infinity
        var previous = vertices.count - 1
        for current in vertices.indices {
            best = min(
                best,
                Self.distance(
                    origin,
                    toSegment: project(vertices[previous]),
                    project(vertices[current]),
                ),
            )
            previous = current
        }
        return best
    }

    private static func distance(
        _ point: PlanarPoint,
        toSegment a: PlanarPoint,
        _ b: PlanarPoint,
    ) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - a.x, point.y - a.y)
        }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        let projectionX = a.x + t * dx
        let projectionY = a.y + t * dy
        return hypot(point.x - projectionX, point.y - projectionY)
    }
}

private struct PlanarPoint {
    let x: Double
    let y: Double
}
