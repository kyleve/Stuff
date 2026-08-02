import Foundation
import RegionKit
import SwiftUI

/// UI-owned cache of projected region paths at the four rendering fidelities
/// Where needs. RegionKit owns/caches source geometry and provides the stateless
/// simplifier; this actor owns display policy and SwiftUI render artifacts.
actor RegionOutlinePathCache {
    enum Resolution: Hashable {
        case full
        case medium
        case small
        case micro

        /// Maximum normalized deviation chosen for each target size. The small
        /// path preserves thin geography such as Long Island inside the stamp;
        /// the coarser micro path remains subpixel at the repeated border's
        /// eight-point glyph size.
        var tolerance: Double? {
            switch self {
                case .full: nil
                case .medium: 1 / 600
                case .small: 1 / 240
                case .micro: 1 / 60
            }
        }
    }

    private struct Key: Hashable {
        let region: Region
        let resolution: Resolution
    }

    private var paths: [Key: Path] = [:]

    func path(for region: Region, resolution: Resolution) async -> Path {
        let key = Key(region: region, resolution: resolution)
        if let cached = paths[key] { return cached }

        let fullOutlines = await RegionGeometryCatalog.outlines(for: region)
        guard !Task.isCancelled else { return Path() }
        // Another caller may have populated this key while the actor was
        // suspended on RegionKit's cache.
        if let cached = paths[key] { return cached }

        let outlines: [RegionOutline]
        do {
            if let tolerance = resolution.tolerance {
                outlines = try RegionGeometrySimplifier.simplify(
                    fullOutlines,
                    tolerance: tolerance,
                )
            } else {
                outlines = fullOutlines
            }
        } catch is CancellationError {
            return Path()
        } catch {
            assertionFailure("Unexpected region simplification failure: \(error)")
            return Path()
        }

        guard !Task.isCancelled else { return Path() }
        let built = Self.makePath(from: outlines, framedBy: fullOutlines)
        paths[key] = built
        return built
    }

    /// Projects every polygon into one reusable path. Two move-only elements
    /// pin `boundingRect` to the full geometry at every resolution; they draw
    /// nothing, but prevent simplification from subtly changing placement.
    private static func makePath(
        from outlines: [RegionOutline],
        framedBy fullOutlines: [RegionOutline],
    ) -> Path {
        guard let projection = Projection(outlines: fullOutlines) else { return Path() }

        var path = Path()
        path.move(to: projection.minimum)
        path.move(to: projection.maximum)
        for outline in outlines {
            guard let first = outline.coordinates.first else { continue }
            path.move(to: projection.point(for: first))
            for coordinate in outline.coordinates.dropFirst() {
                path.addLine(to: projection.point(for: coordinate))
            }
            path.closeSubpath()
        }
        return path
    }

    private struct Projection {
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
    }
}

extension EnvironmentValues {
    /// The scene/root-owned render cache. Optional only so a component rendered
    /// without `whereBroadwayRoot()` can fall back to its symbol treatment.
    @Entry var regionOutlinePathCache: RegionOutlinePathCache?
}
