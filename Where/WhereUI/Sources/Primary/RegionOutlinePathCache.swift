import Foundation
import RegionKit
import SwiftUI
import WhereCore

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
    private var projections: [Region: RegionArtworkProjection] = [:]

    private func projection(
        for region: Region,
        outlines: [RegionOutline],
    ) -> RegionArtworkProjection? {
        if let cached = projections[region] {
            return cached
        }
        let projection = RegionArtworkProjection(outlines: outlines)
        projections[region] = projection
        return projection
    }

    func path(for region: Region, resolution: Resolution) async -> Path {
        let key = Key(region: region, resolution: resolution)
        if let cached = paths[key] {
            return cached
        }

        let fullOutlines = await RegionGeometryCatalog.displayOutlines(for: region)
        guard !Task.isCancelled else { return Path() }
        // Another caller may have populated this key while the actor was
        // suspended on RegionKit's cache.
        if let cached = paths[key] {
            return cached
        }

        guard let projection = projection(for: region, outlines: fullOutlines)
        else { return Path() }
        let longestSide = max(
            projection.maximum.x - projection.minimum.x,
            projection.maximum.y - projection.minimum.y,
        )
        let minimumExtent = longestSide * (resolution.tolerance ?? 0)
        let outlines: [RegionOutline]
        do {
            if let tolerance = resolution.tolerance {
                let visible = try fullOutlines.filter {
                    try Task.checkCancellation()
                    return projection.reachesExtent(minimumExtent, ring: $0.coordinates)
                }
                outlines = try RegionGeometrySimplifier.simplify(
                    visible,
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
        let built = projection.path(from: outlines, minimumHoleExtent: minimumExtent)
        paths[key] = built
        return built
    }

    /// Projects raw fixes into the same local coordinate space as every cached
    /// path. Selection remains UI policy and is applied by the card after this
    /// method returns; user locations are never retained by this shared cache.
    func projectedPoints(
        for region: Region,
        points: [RegionDayPoint],
    ) async -> [RegionLocationConstellationLayout.Point] {
        guard points.isEmpty == false else { return [] }
        let outlines = await RegionGeometryCatalog.displayOutlines(for: region)
        guard
            Task.isCancelled == false,
            let projection = projection(for: region, outlines: outlines)
        else { return [] }
        return points.map {
            RegionLocationConstellationLayout.Point(
                position: projection.point(for: $0.coordinate),
                horizontalAccuracy: $0.horizontalAccuracy,
            )
        }
    }
}

extension EnvironmentValues {
    /// The scene/root-owned render cache. Optional only so a component rendered
    /// without `whereBroadwayRoot()` can fall back to its symbol treatment.
    @Entry var regionOutlinePathCache: RegionOutlinePathCache?
}
