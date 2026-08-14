import Foundation
import PeriscopeCore

/// A coordinate-to-`Region` lookup engine. Abstracted as a protocol so callers
/// can hold either an immutable ``RegionAttributor`` snapshot or a live,
/// swappable attributor (e.g. one WhereCore rebuilds when the user's tracked
/// regions change) behind the same synchronous API.
public protocol RegionAttributing: Sendable {
    /// The region `coordinate` falls inside, or `.other` if none.
    func region(at coordinate: Coordinate) -> Region
    /// Smallest distance in meters from `coordinate` to `region`'s boundary, or
    /// `nil` for a region this attributor didn't load.
    func distanceToBoundary(of region: Region, from coordinate: Coordinate) -> Double?
    /// The regions this attributor loaded and attributes to (excludes `.other`).
    var loadedRegions: [Region] { get }
}

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
public struct RegionAttributor: RegionAttributing {
    private let regionPolygons: [RegionPolygons]

    /// Attributor for the default set of tracked regions (California, New York,
    /// Canada, the European Union). Production derives its attributor from the
    /// store's tracked regions via `WhereServices.make(...)`; this snapshot backs
    /// the synchronous defaults for tests and previews (whose in-memory stores
    /// resolve to this same default) and the "no tracked rows yet" fallback. The
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

    /// The regions this attributor loaded, in load order (excludes `.other`).
    public var loadedRegions: [Region] {
        regionPolygons.map(\.region)
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

    /// `RegionLog` logger — surfaces missing/unparseable bundled resources as
    /// Console.app faults alongside the debug-build `assertionFailure`.
    private static let logger = RegionLog.attributor

    /// Loads the exterior-ring polygons for each region from its bundled
    /// per-region GeoJSON. Missing/corrupt geometry is a programmer error: it's
    /// logged as a `fault` and `assertionFailure`s in debug, degrading to
    /// "region simply never matches" in release rather than crashing.
    private static func loadPolygons(for regions: [Region]) -> [RegionPolygons] {
        var entries: [RegionPolygons] = []
        logger.measure(.loadPolygons, budget: .seconds(1)) {
            for region in regions {
                guard region != .other else { continue }
                guard let url = RegionCatalog.shared.geometryURL(for: region) else {
                    logger.missingGeometry(region: .restricted(.location, region))
                    assertionFailure("Missing bundled GeoJSON for region \(region.rawValue)")
                    continue
                }
                do {
                    let polygons = try logger.measure(.loadRegion(region)) {
                        try GeoJSON.polygons(at: url)
                    }
                    guard !polygons.isEmpty else {
                        logger.emptyPolygons(region: .restricted(.location, region))
                        assertionFailure("Region \(region.rawValue) decoded no polygons")
                        continue
                    }
                    entries.append(RegionPolygons(region: region, polygons: polygons))
                } catch {
                    logger.decodeFailed(
                        region: .restricted(.location, region),
                        description: .restricted(.errorDetails, error.localizedDescription),
                        attachments: [.error(error, name: "decode-error")],
                    )
                    assertionFailure(
                        "Failed to decode bundled GeoJSON for region \(region.rawValue): \(error)",
                    )
                }
            }
        }
        logger.loaded(regionCount: .shared(.count, entries.count))
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
