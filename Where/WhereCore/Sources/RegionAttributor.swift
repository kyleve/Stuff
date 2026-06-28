import Foundation
import LogKit

/// Maps coordinates to the tracked `Region` they fall inside. Backed by a
/// list of polygons per region; checked in declaration order so the first
/// match wins (regions are mutually exclusive at our resolution).
///
/// Polygons are loaded from bundled GeoJSON in `Resources/` via the
/// `GeoJSON` namespace, driven entirely by each region's
/// `Region.geometrySource`:
/// - `.usStateFeature(name:)` regions (`.california`, `.newYork`, ...)
///   come out of a single `us-states.geojson` indexed by feature `NAME`.
///   Adding another US state is just a new `Region` case whose
///   `geometrySource` names its Census feature — no new file to bundle.
/// - `.bundledFile` regions (`.canada`, `.europeanUnion`) keep a
///   dedicated per-region file named after the enum `rawValue`.
///
/// Regions are loaded in `Region.allCases` order, which fixes the
/// first-match priority in `region(at:)`. Anything not inside any
/// bundled polygon (and any `.none` region, e.g. `.other`) is `.other`.
public struct RegionAttributor: Sendable {
    private let regionPolygons: [RegionPolygons]

    public static let shared: RegionAttributor = .loadFromBundle()

    init(regionPolygons: [RegionPolygons]) {
        self.regionPolygons = regionPolygons
    }

    public func region(at coordinate: Coordinate) -> Region {
        // Per-region bounding-box pre-pass: cheap rectangular comparison
        // rejects coordinates that can't possibly be inside the
        // polygons for this region before the more expensive
        // even-odd ray-cast runs. For our 4-region set the boxes
        // barely overlap (CA / NY / Canada / EU), so a typical
        // out-of-set coordinate fails the bbox check 4 times in a row
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
    /// `region`'s bundled polygons. Returns `nil` for regions without
    /// polygons (e.g. `.other`).
    public func distanceToBoundary(of region: Region, from coordinate: Coordinate) -> Double? {
        guard let entry = regionPolygons.first(where: { $0.region == region }) else { return nil }
        return entry.polygons.map { $0.distanceToBoundary(from: coordinate) }.min()
    }

    /// `Logger` from `os` — used in `loadFromBundle` to surface
    /// missing/unparseable bundled resources as Console.app faults
    /// alongside the debug-build `assertionFailure`.
    private static let logger = WhereLog.channel(.regionAttributor)

    private static func loadFromBundle() -> RegionAttributor {
        // Every Census `NAME` any `.usStateFeature` region wants, so the
        // shared `us-states.geojson` is read and indexed in a single pass.
        let wantedStateNames = Set(Region.allCases.compactMap { region -> String? in
            guard case let .usStateFeature(name) = region.geometrySource else { return nil }
            return name
        })
        let usStateIndex = loadUSStateIndex(matching: wantedStateNames)

        // `Region.allCases` order fixes the first-match priority in
        // `region(at:)`; `.none` regions (e.g. `.other`) contribute no
        // polygons and are skipped.
        var entries: [RegionPolygons] = []
        for region in Region.allCases {
            switch region.geometrySource {
                case let .usStateFeature(name):
                    if let polygons = usStateIndex[name] {
                        entries.append(RegionPolygons(region: region, polygons: polygons))
                    } else {
                        // Either the bundle resource is missing entirely (caught
                        // upstream and logged) or the named feature isn't in the
                        // file. Either way, this region would silently attribute
                        // to `.other`; surface it via fault + assertionFailure.
                        logger
                            .fault(
                                "Missing feature \(name) in bundled us-states.geojson for region \(region.rawValue)",
                            )
                        assertionFailure(
                            "Missing feature \(name) in us-states.geojson for region \(region.rawValue)",
                        )
                    }

                case .bundledFile:
                    guard let url = Bundle.module
                        .url(forResource: region.rawValue, withExtension: "geojson")
                    else {
                        logger
                            .fault(
                                "Missing required bundled GeoJSON for region \(region.rawValue)",
                            )
                        assertionFailure("Missing bundled GeoJSON for region \(region.rawValue)")
                        continue
                    }
                    do {
                        let polygons = try GeoJSON.polygons(at: url)
                        entries.append(RegionPolygons(region: region, polygons: polygons))
                    } catch {
                        logger
                            .fault(
                                "Failed to decode bundled GeoJSON \(region.rawValue): \(error.localizedDescription)",
                            )
                        assertionFailure(
                            "Failed to decode bundled GeoJSON \(region.rawValue): \(error)",
                        )
                    }

                case .none:
                    continue
            }
        }
        logger.info("Loaded region polygons for \(entries.count) region(s)")
        return RegionAttributor(regionPolygons: entries)
    }

    /// Loads `us-states.geojson`, decodes only the features whose
    /// `properties.NAME` is in `wanted`, and returns
    /// `[NAME: [GeoPolygon]]`. Returns `[:]` (with logging) if the file is
    /// missing or unparseable; callers then fall back to per-region
    /// `assertionFailure` reporting so the diagnostic is attached to the
    /// missing-state name rather than the file as a whole.
    private static func loadUSStateIndex(matching wanted: Set<String>) -> [String: [GeoPolygon]] {
        guard let url = Bundle.module.url(forResource: "us-states", withExtension: "geojson") else {
            logger.fault("Missing required bundled us-states.geojson")
            assertionFailure("Missing bundled us-states.geojson")
            return [:]
        }
        do {
            var index: [String: [GeoPolygon]] = [:]
            for feature in try GeoJSON.namedPolygons(at: url) {
                guard let name = feature.name, wanted.contains(name) else { continue }
                index[name, default: []].append(contentsOf: feature.polygons)
            }
            logger.info("Indexed \(index.count) US state(s) from us-states.geojson")
            return index
        } catch {
            logger
                .fault(
                    "Failed to decode bundled us-states.geojson: \(error.localizedDescription)",
                )
            assertionFailure("Failed to decode bundled us-states.geojson: \(error)")
            return [:]
        }
    }
}

/// One `Region` plus every polygon that defines it. Replaces an earlier
/// `(region, polygons)` tuple so the value carries a name and a
/// precomputed `boundingBox` for fast pre-screening in
/// `RegionAttributor.region(at:)`.
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
            // Empty polygon set is a programmer error — every caller
            // here is the bundle loader, which `assertionFailure`s
            // before constructing a `RegionPolygons` with no
            // polygons. The release-build fallback is `.empty`, a
            // degenerate bbox that contains nothing, so the region
            // simply never matches (failing to `.other` is preferable
            // to a crash in production for what is fundamentally a
            // missing-data condition).
            assertionFailure(
                "Cannot construct RegionPolygons with no polygons for \(region.rawValue)",
            )
            boundingBox = .empty
        }
    }
}
