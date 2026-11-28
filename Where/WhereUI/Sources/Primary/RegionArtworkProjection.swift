import CoreGraphics
import RegionKit
import SwiftUI

/// Projects region geometry and recorded coordinates into the same local space.
/// The longitude span is antimeridian-aware and longitude is corrected at the
/// region's mid-latitude so silhouettes and GPS constellations stay aligned.
struct RegionArtworkProjection {
    let centerLongitude: Double
    let midLatitude: Double
    let longitudeCorrection: Double
    let minimum: CGPoint
    let maximum: CGPoint

    init?(outlines: [RegionOutline]) {
        guard let box = BoundingBox.enclosing(outlines),
              let longitudeSpan = LongitudeSpan.enclosing(outlines, boundedBy: box)
        else { return nil }

        centerLongitude = longitudeSpan.center
        midLatitude = (box.minLatitude + box.maxLatitude) / 2
        longitudeCorrection = max(cos(midLatitude * .pi / 180), 0.1)
        let halfWidth = longitudeSpan.degrees * longitudeCorrection / 2
        let halfHeight = (box.maxLatitude - box.minLatitude) / 2
        minimum = CGPoint(x: -halfWidth, y: -halfHeight)
        maximum = CGPoint(x: halfWidth, y: halfHeight)
    }

    func point(for coordinate: Coordinate) -> CGPoint {
        let longitudeDelta = (coordinate.longitude - centerLongitude + 540)
            .truncatingRemainder(dividingBy: 360) - 180
        return CGPoint(
            x: longitudeDelta * longitudeCorrection,
            y: midLatitude - coordinate.latitude,
        )
    }

    /// Stop as soon as this part reaches the drawing tolerance. Tiny islands
    /// and lake holes can then be omitted before simplifying or building paths.
    func reachesExtent(_ extent: CGFloat, ring: [Coordinate]) -> Bool {
        guard extent > 0 else { return true }
        guard let first = ring.first else { return false }
        let origin = point(for: first)
        var minX = origin.x, maxX = origin.x, minY = origin.y, maxY = origin.y
        for vertex in ring.dropFirst() {
            let point = point(for: vertex)
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
            if maxX - minX >= extent || maxY - minY >= extent {
                return true
            }
        }
        return false
    }

    /// Build a path pinned to the full projection bounds. The two move-only
    /// elements draw nothing but keep simplified paths framed identically.
    func path(from outlines: [RegionOutline], minimumHoleExtent: CGFloat = 0) -> Path {
        var path = Path()
        path.move(to: minimum)
        path.move(to: maximum)
        func add(ring: [Coordinate]) {
            guard let first = ring.first else { return }
            path.move(to: point(for: first))
            for coordinate in ring.dropFirst() {
                path.addLine(to: point(for: coordinate))
            }
            path.closeSubpath()
        }
        for outline in outlines {
            add(ring: outline.coordinates)
            for hole in outline.holes
                where reachesExtent(minimumHoleExtent, ring: hole)
            {
                add(ring: hole)
            }
        }
        return path
    }
}
