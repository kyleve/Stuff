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
        guard
            let box = BoundingBox.enclosing(outlines),
            let longitudeSpan = LongitudeSpan.enclosing(
                outlines.lazy.flatMap { outline in
                    outline.coordinates.lazy.map(\.longitude)
                },
            )
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

    /// Build a path pinned to the full projection bounds. The two move-only
    /// elements draw nothing but keep simplified paths framed identically.
    func path(from outlines: [RegionOutline]) -> Path {
        var path = Path()
        path.move(to: minimum)
        path.move(to: maximum)
        for outline in outlines {
            guard let first = outline.coordinates.first else { continue }
            path.move(to: point(for: first))
            for coordinate in outline.coordinates.dropFirst() {
                path.addLine(to: point(for: coordinate))
            }
            path.closeSubpath()
        }
        return path
    }
}
