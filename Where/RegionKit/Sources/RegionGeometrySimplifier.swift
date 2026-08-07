import Foundation

/// Simplifies drawable region geometry with an antimeridian-aware planar
/// projection while preserving every polygon and its stable identity.
public enum RegionGeometrySimplifier {
    /// Returns outlines simplified with Ramer-Douglas-Peucker.
    ///
    /// `tolerance` is expressed as a fraction of the complete region's longest
    /// projected dimension. For example, `1 / 600` discards deviations smaller
    /// than roughly half a point when rendered 300 points wide. A non-positive
    /// tolerance returns `outlines` unchanged. Cancellation is checked while
    /// processing detailed boundaries and is surfaced to the caller.
    public static func simplify(
        _ outlines: [RegionOutline],
        tolerance: Double,
    ) throws -> [RegionOutline] {
        guard tolerance > 0 else { return outlines }
        guard
            let box = BoundingBox.enclosing(outlines),
            let longitudeSpan = LongitudeSpan.enclosing(
                outlines.lazy.flatMap { outline in
                    outline.coordinates.lazy.map(\.longitude)
                },
            )
        else { return [] }

        let projection = Projection(box: box, longitudeSpan: longitudeSpan)
        return try outlines.map { outline in
            try Task.checkCancellation()
            return try RegionOutline(
                id: outline.id,
                title: outline.title,
                region: outline.region,
                coordinates: simplifyRing(
                    outline.coordinates,
                    tolerance: tolerance,
                    projection: projection,
                ),
            )
        }
    }

    /// Simplifies a closed polygon by splitting it into two open arcs and
    /// applying Ramer-Douglas-Peucker to each. This avoids the coincident
    /// first/last endpoint problem of treating a ring as one open line.
    private static func simplifyRing(
        _ coordinates: [Coordinate],
        tolerance: Double,
        projection: Projection,
    ) throws -> [Coordinate] {
        let ring = normalizedRing(coordinates)
        guard ring.count > 3 else { return ring }

        let points = ring.map(projection.point(for:))
        let splitIndex = farthestPointIndex(from: points[0], in: points)
        guard splitIndex > 0, splitIndex < ring.count else { return ring }

        let firstArc = Array(0 ... splitIndex)
        let secondArc = Array(splitIndex ..< ring.count) + [0]
        let firstKept = try simplifyOpenLine(firstArc, points: points, tolerance: tolerance)
        let secondKept = try simplifyOpenLine(secondArc, points: points, tolerance: tolerance)
        let kept = firstKept + secondKept.dropFirst().dropLast()

        // Each authored polygon remains a drawable polygon at every tolerance.
        // Extremely tiny islands may simplify to a line; retain three ordered
        // source vertices for those rather than dropping the island entirely.
        guard kept.count >= 3 else {
            return [ring[0], ring[ring.count / 3], ring[(ring.count * 2) / 3]]
        }
        return kept.map { ring[$0] }
    }

    /// Removes only redundant closure/consecutive vertices. The returned ring
    /// relies on renderers closing the path, matching `RegionOutline`'s API.
    private static func normalizedRing(_ coordinates: [Coordinate]) -> [Coordinate] {
        var result: [Coordinate] = []
        result.reserveCapacity(coordinates.count)
        for coordinate in coordinates where coordinate != result.last {
            result.append(coordinate)
        }
        if result.count > 3, result.first == result.last {
            result.removeLast()
        }
        return result
    }

    private static func farthestPointIndex(from origin: Point, in points: [Point]) -> Int {
        var farthestIndex = 0
        var farthestDistanceSquared = 0.0
        for index in points.indices.dropFirst() {
            let distanceSquared = points[index].distanceSquared(to: origin)
            if distanceSquared > farthestDistanceSquared {
                farthestIndex = index
                farthestDistanceSquared = distanceSquared
            }
        }
        return farthestIndex
    }

    /// Iterative Ramer-Douglas-Peucker over source indices. An explicit stack
    /// avoids recursion depth growing with a particularly detailed boundary.
    private static func simplifyOpenLine(
        _ indices: [Int],
        points: [Point],
        tolerance: Double,
    ) throws -> [Int] {
        guard indices.count > 2 else { return indices }
        let toleranceSquared = tolerance * tolerance
        var keep = Array(repeating: false, count: indices.count)
        keep[0] = true
        keep[indices.count - 1] = true
        var segments = [Segment(first: 0, last: indices.count - 1)]
        var inspectedPointCount = 0

        while let segment = segments.popLast() {
            guard segment.last - segment.first > 1 else { continue }
            let start = points[indices[segment.first]]
            let end = points[indices[segment.last]]
            var farthestOffset: Int?
            var farthestDistanceSquared = toleranceSquared

            for offset in (segment.first + 1) ..< segment.last {
                inspectedPointCount += 1
                if inspectedPointCount.isMultiple(of: 256) {
                    try Task.checkCancellation()
                }
                let distanceSquared = points[indices[offset]].distanceSquared(
                    toSegmentFrom: start,
                    to: end,
                )
                if distanceSquared > farthestDistanceSquared {
                    farthestOffset = offset
                    farthestDistanceSquared = distanceSquared
                }
            }

            if let farthestOffset {
                keep[farthestOffset] = true
                segments.append(Segment(first: segment.first, last: farthestOffset))
                segments.append(Segment(first: farthestOffset, last: segment.last))
            }
        }

        return indices.enumerated().compactMap { offset, index in
            keep[offset] ? index : nil
        }
    }

    private struct Projection {
        let centerLongitude: Double
        let midLatitude: Double
        let longitudeCorrection: Double
        let normalizationScale: Double

        init(box: BoundingBox, longitudeSpan: LongitudeSpan) {
            centerLongitude = longitudeSpan.center
            midLatitude = (box.minLatitude + box.maxLatitude) / 2
            longitudeCorrection = max(cos(midLatitude * .pi / 180), 0.1)
            let latitudeSpan = max(box.maxLatitude - box.minLatitude, 0.0001)
            let projectedLongitudeSpan = max(
                longitudeSpan.degrees * longitudeCorrection,
                0.0001,
            )
            normalizationScale = max(latitudeSpan, projectedLongitudeSpan)
        }

        func point(for coordinate: Coordinate) -> Point {
            let longitudeDelta = (coordinate.longitude - centerLongitude + 540)
                .truncatingRemainder(dividingBy: 360) - 180
            return Point(
                x: longitudeDelta * longitudeCorrection / normalizationScale,
                y: (coordinate.latitude - midLatitude) / normalizationScale,
            )
        }
    }

    private struct Point {
        let x: Double
        let y: Double

        func distanceSquared(to other: Point) -> Double {
            let dx = x - other.x
            let dy = y - other.y
            return dx * dx + dy * dy
        }

        func distanceSquared(toSegmentFrom start: Point, to end: Point) -> Double {
            let dx = end.x - start.x
            let dy = end.y - start.y
            let lengthSquared = dx * dx + dy * dy
            guard lengthSquared > 0 else { return distanceSquared(to: start) }
            let t = max(0, min(1, ((x - start.x) * dx + (y - start.y) * dy) / lengthSquared))
            let projection = Point(x: start.x + t * dx, y: start.y + t * dy)
            return distanceSquared(to: projection)
        }
    }

    private struct Segment {
        let first: Int
        let last: Int
    }
}
