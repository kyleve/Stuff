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

    func enclosing(_ other: Self) -> Self {
        Self(
            minLatitude: min(minLatitude, other.minLatitude),
            maxLatitude: max(maxLatitude, other.maxLatitude),
            minLongitude: min(minLongitude, other.minLongitude),
            maxLongitude: max(maxLongitude, other.maxLongitude),
        )
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
    /// (which never happens with bundled geometry; the optional is
    /// there so the helper is safe to use on arbitrary inputs too).
    static func enclosing(_ polygons: [GeoPolygon]) -> BoundingBox? {
        guard let first = polygons.first(where: { !$0.vertices.isEmpty }) else { return nil }
        return polygons.reduce(first.geographicBounds) { box, polygon in
            let next = polygon.geographicBounds
            return BoundingBox(
                minLatitude: min(box.minLatitude, next.minLatitude),
                maxLatitude: max(box.maxLatitude, next.maxLatitude),
                minLongitude: min(box.minLongitude, next.minLongitude),
                maxLongitude: max(box.maxLongitude, next.maxLongitude),
            )
        }
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

/// Polygon containment and distances in the local longitude/latitude plane.
/// Each polygon has an exterior ring and any holes it encloses.
struct GeoPolygon: Hashable {
    let vertices: [Coordinate]
    let holes: [[Coordinate]]
    private let bounds: BoundingBox
    private let crossesAntimeridian: Bool
    private let edgeGroups: [EdgeGroup]

    /// Consecutive edges on a detailed coast are usually close together. Their
    /// bounds let both ray casting and distance skip whole stretches of coastline.
    private struct EdgeGroup: Hashable {
        let edges: Range<Int>
        let bounds: BoundingBox
    }

    init(vertices: [Coordinate], holes: [[Coordinate]] = []) {
        self.vertices = vertices
        self.holes = holes
        let box = BoundingBox.enclosing(vertices) ?? .empty
        crossesAntimeridian = box.maxLongitude - box.minLongitude > 180 &&
            zip(vertices, vertices.dropFirst() + vertices.prefix(1)).contains {
                abs($0.longitude - $1.longitude) > 180
            }
        if crossesAntimeridian {
            bounds = BoundingBox.enclosing(vertices.lazy.map {
                Coordinate(
                    latitude: $0.latitude,
                    longitude: $0.longitude < 0 ? $0.longitude + 360 : $0.longitude,
                )
            }) ?? .empty
        } else {
            bounds = box
        }
        if vertices.count > 512, !crossesAntimeridian {
            var groups: [EdgeGroup] = []
            for start in stride(from: 0, to: vertices.count, by: 64) {
                let end = min(start + 64, vertices.count)
                let preceding = vertices[start == 0 ? vertices.count - 1 : start - 1]
                let points = vertices[start ..< end]
                if let box = BoundingBox.enclosing(points) {
                    groups.append(EdgeGroup(edges: start ..< end, bounds: BoundingBox(
                        minLatitude: min(box.minLatitude, preceding.latitude),
                        maxLatitude: max(box.maxLatitude, preceding.latitude),
                        minLongitude: min(box.minLongitude, preceding.longitude),
                        maxLongitude: max(box.maxLongitude, preceding.longitude),
                    )))
                }
            }
            edgeGroups = groups
        } else {
            edgeGroups = []
        }
    }

    var geographicBounds: BoundingBox {
        guard crossesAntimeridian else { return bounds }
        return BoundingBox(
            minLatitude: bounds.minLatitude,
            maxLatitude: bounds.maxLatitude,
            minLongitude: -180,
            maxLongitude: 180,
        )
    }

    private func longitude(_ value: Double) -> Double {
        crossesAntimeridian && value < 0 ? value + 360 : value
    }

    func contains(_ coordinate: Coordinate) -> Bool {
        let x = longitude(coordinate.longitude)
        let y = coordinate.latitude
        guard x >= bounds.minLongitude, x <= bounds.maxLongitude,
              y >= bounds.minLatitude, y <= bounds.maxLatitude else { return false }
        var inside = false
        if edgeGroups.isEmpty {
            inside = crosses(x: x, y: y, ring: vertices, edges: vertices.indices)
        } else {
            for group in edgeGroups
                where y >= group.bounds.minLatitude && y < group.bounds.maxLatitude && x <= group
                .bounds.maxLongitude
            {
                if crosses(x: x, y: y, ring: vertices, edges: group.edges) { inside.toggle() }
            }
        }
        return inside && !holes.contains { crosses(x: x, y: y, ring: $0, edges: $0.indices) }
    }

    private func crosses(x: Double, y: Double, ring: [Coordinate], edges: Range<Int>) -> Bool {
        guard ring.isValidPolygonRing, !edges.isEmpty else { return false }
        var previous = ring[edges.lowerBound == 0 ? ring.count - 1 : edges.lowerBound - 1]
        var odd = false
        for index in edges {
            let current = ring[index]
            if (current.latitude > y) != (previous.latitude > y) {
                let fraction = (y - current.latitude) / (previous.latitude - current.latitude)
                let start = longitude(current.longitude)
                if x < start + fraction * (longitude(previous.longitude) - start) { odd.toggle() }
            }
            previous = current
        }
        return odd
    }

    /// The boundary converter preserves exactly matching edges between adjacent
    /// subdivisions. A reversed edge represents the same internal border.
    func hasEdge(_ a: Coordinate, _ b: Coordinate) -> Bool {
        guard a != b, geographicBounds.contains(a), geographicBounds.contains(b) else {
            return false
        }
        func matches(_ ring: [Coordinate], edges: Range<Int>) -> Bool {
            guard !edges.isEmpty else { return false }
            var previous = ring[edges.lowerBound == 0 ? ring.count - 1 : edges.lowerBound - 1]
            for index in edges {
                let current = ring[index]
                if (previous == a && current == b) ||
                    (previous == b && current == a) { return true }
                previous = current
            }
            return false
        }
        if edgeGroups.isEmpty {
            if matches(vertices, edges: vertices.indices) { return true }
        } else if edgeGroups.contains(where: {
            $0.bounds.contains(a) && $0.bounds.contains(b) && matches(vertices, edges: $0.edges)
        }) {
            return true
        }
        return holes.contains { matches($0, edges: $0.indices) }
    }

    /// Closest boundary in metres, including holes. The box lower bound avoids
    /// walking an island's coastline when a nearer edge has already been found.
    func distanceToBoundary(
        from coordinate: Coordinate,
        nearerThan bestSoFar: Double = .infinity,
        includingEdge: (Coordinate, Coordinate) -> Bool = { _, _ in true },
    ) -> Double {
        guard vertices.count >= 2 else { return bestSoFar }
        let latitudeScale = 111_320.0
        let longitudeScale = latitudeScale * cos(coordinate.latitude * .pi / 180)
        var x = longitude(coordinate.longitude)
        let mid = (bounds.maxLongitude + bounds.minLongitude) / 2
        if x - mid > 180 { x -= 360 } else if mid - x > 180 { x += 360 }
        let y = coordinate.latitude
        func lowerBoundSquared(_ box: BoundingBox) -> Double {
            let dx = max(box.minLongitude - x, x - box.maxLongitude, 0) * longitudeScale
            let dy = max(box.minLatitude - y, y - box.maxLatitude, 0) * latitudeScale
            return dx * dx + dy * dy
        }
        guard lowerBoundSquared(bounds) < bestSoFar * bestSoFar else { return bestSoFar }
        func project(_ c: Coordinate) -> PlanarPoint {
            PlanarPoint(
                x: (longitude(c.longitude) - x) * longitudeScale,
                y: (c.latitude - y) * latitudeScale,
            )
        }
        let origin = PlanarPoint(x: 0, y: 0)
        var best = bestSoFar
        func visit(_ ring: [Coordinate], edges: Range<Int>) {
            guard !edges.isEmpty else { return }
            var previous = ring[edges.lowerBound == 0 ? ring.count - 1 : edges.lowerBound - 1]
            var start = project(previous)
            for index in edges {
                let vertex = ring[index]
                let end = project(vertex)
                // Rings may repeat their first point at the end. The zero-length
                // closure is not a separate exterior edge at a subdivision seam.
                if vertex != previous {
                    let distance = Self.distance(origin, toSegment: start, end)
                    if distance < best, includingEdge(previous, vertex) { best = distance }
                }
                previous = vertex
                start = end
            }
        }
        if edgeGroups.isEmpty {
            visit(vertices, edges: vertices.indices)
        } else {
            for group in edgeGroups where lowerBoundSquared(group.bounds) < best * best {
                visit(vertices, edges: group.edges)
            }
        }
        for hole in holes {
            visit(hole, edges: hole.indices)
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
