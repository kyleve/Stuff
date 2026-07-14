import Foundation
import LogKit

/// Maps coordinates to the `Region` they fall inside. Backed by a list of
/// polygons per region, checked in order so the first match wins (regions are
/// mutually exclusive at our resolution).
///
/// An attributor is built for a **specific set of regions** and loads only
/// those regions' bundled GeoJSON (one `Resources/regions/<id>.geojson` per
/// region, named by ``RegionCatalog``), so we never parse regions we don't
/// track. The order of the regions passed to ``init(for:)`` fixes the
/// first-match priority in ``region(at:)``. Anything outside every loaded
/// region (and `.other` itself, which has no geometry) is `.other`.
public struct RegionAttributor: Sendable {
    private let regionPolygons: [RegionPolygons]

    /// Attributor for the regions the app has historically tracked. Kept as a
    /// convenience while the app's tracked set moves into the store; the
    /// developer viewer and tests use ``all`` for the whole catalog.
    public static let shared = RegionAttributor(for: [
        .california,
        .newYork,
        .canada,
        .europeanUnion,
    ])

    /// Attributor covering **every** available region in the catalog. Loads all
    /// per-region files, so reserve it for the developer region-map viewer and
    /// tests — production attributes against the user's tracked subset.
    public static let all = RegionAttributor(for: RegionCatalog.shared.all)

    /// Builds an attributor that loads and attributes only `regions` (in the
    /// given order, which fixes first-match priority). `.other` is ignored — it
    /// has no geometry and is the fallback when nothing matches.
    public init(for regions: [Region]) {
        regionPolygons = Self.loadPolygons(for: regions)
    }

    init(regionPolygons: [RegionPolygons]) {
        self.regionPolygons = regionPolygons
    }

    /// The loaded polygons per region, exposed for the developer region-map
    /// viewer (`RegionGeometryCatalog`). Internal on purpose: callers outside
    /// `RegionKit` consume drawable outlines via
    /// `RegionGeometryCatalog.outlines(for:)`, never raw `RegionPolygons`.
    var loadedRegionPolygons: [RegionPolygons] {
        regionPolygons
    }

    public func region(at coordinate: Coordinate) -> Region {
        // Per-region bounding-box pre-pass: a cheap rectangular comparison
        // rejects coordinates that can't be inside a region's polygons before
        // the more expensive even-odd ray-cast runs. Region boxes barely
        // overlap, so a typical out-of-set coordinate fails every bbox check
        // and never enters `polygon.contains`.
        for entry in regionPolygons {
            guard entry.boundingBox.contains(coordinate) else { continue }
            for polygon in entry.polygons {
                if polygon.contains(coordinate) {
                    return entry.region
                }
            }
        }
        return .other
    }

    /// Smallest distance in meters from `coordinate` to the boundary of
    /// `region`'s loaded polygons. Returns `nil` for regions this attributor
    /// didn't load (including `.other`).
    public func distanceToBoundary(of region: Region, from coordinate: Coordinate) -> Double? {
        guard let entry = regionPolygons.first(where: { $0.region == region }) else { return nil }
        return entry.polygons.map { $0.distanceToBoundary(from: coordinate) }.min()
    }

    /// `RegionLog` channel — surfaces missing/unparseable bundled resources as
    /// Console.app faults alongside the debug-build `assertionFailure`.
    private static let logger = RegionLog.channel(.attributor)

    /// Loads the exterior-ring polygons for each region from its bundled
    /// per-region GeoJSON. Missing/corrupt geometry is a programmer error: it's
    /// logged as a `fault` and `assertionFailure`s in debug, degrading to
    /// "region simply never matches" in release rather than crashing.
    private static func loadPolygons(for regions: [Region]) -> [RegionPolygons] {
        var entries: [RegionPolygons] = []
        for region in regions {
            guard region != .other else { continue }
            guard let url = RegionCatalog.shared.geometryURL(for: region) else {
                logger.fault("Missing bundled GeoJSON for region \(region.rawValue)")
                assertionFailure("Missing bundled GeoJSON for region \(region.rawValue)")
                continue
            }
            do {
                let polygons = try GeoJSON.polygons(at: url)
                guard !polygons.isEmpty else {
                    logger.fault("Region \(region.rawValue) decoded no polygons")
                    assertionFailure("Region \(region.rawValue) decoded no polygons")
                    continue
                }
                entries.append(RegionPolygons(region: region, polygons: polygons))
            } catch {
                logger
                    .fault(
                        "Failed to decode bundled GeoJSON for region \(region.rawValue): \(error.localizedDescription)",
                    )
                assertionFailure(
                    "Failed to decode bundled GeoJSON for region \(region.rawValue): \(error)",
                )
            }
        }
        logger.info("Loaded region polygons for \(entries.count) region(s)")
        return entries
    }
}

/// One `Region` plus every polygon that defines it, with a precomputed
/// `boundingBox` for fast pre-screening in `RegionAttributor.region(at:)`.
struct RegionPolygons {
    let region: Region
    let polygons: [GeoPolygon]
    let boundingBox: BoundingBox

    init(region: Region, polygons: [GeoPolygon]) {
        self.region = region
        self.polygons = polygons
        if let box = BoundingBox.enclosing(polygons) {
            boundingBox = box
        } else {
            // Empty polygon set is a programmer error — the loader guards
            // against it before constructing a `RegionPolygons`. The
            // release-build fallback is `.empty`, a degenerate bbox that
            // contains nothing, so the region simply never matches (failing to
            // `.other` beats crashing on a missing-data condition).
            assertionFailure(
                "Cannot construct RegionPolygons with no polygons for \(region.rawValue)",
            )
            boundingBox = .empty
        }
    }
}
