import Foundation
import LogKit

/// Maps coordinates to the tracked `Region` they fall inside. Backed by a
/// list of polygons per region; checked in declaration order so the first
/// match wins (regions are mutually exclusive at our resolution).
///
/// Polygons are loaded from bundled GeoJSON in `Resources/` via the
/// `GeoJSON` namespace:
/// - US states (`Region.california`, `Region.newYork`, ...) come out of a
///   single `us-states.geojson` indexed by feature `NAME`. Adding another
///   US state is just a new `Region` case plus an entry in `usStateNames`
///   below — no new file to bundle.
/// - Non-US regions (`.canada`, `.europeanUnion`) keep a dedicated
///   per-region file named after the enum `rawValue`.
///
/// Anything not inside any bundled polygon is `.other`.
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

    /// `Logger` from `os` — used in `loadFromBundle` to surface
    /// missing/unparseable bundled resources as Console.app faults
    /// alongside the debug-build `assertionFailure`.
    private static let logger = WhereLog.channel(.regionAttributor)

    /// `Region` cases that resolve to a US state in `us-states.geojson`.
    /// The value is the GeoJSON feature's `properties.NAME` — **a data
    /// identifier for matching against the bundled file**, never
    /// shown to the user. User-facing labels go through
    /// `Region.localizedName` (string catalog) instead.
    private static let usStateNames: [Region: String] = [
        .california: "California",
        .newYork: "New York",
    ]

    private static func loadFromBundle() -> RegionAttributor {
        let regions: [Region] = [.california, .newYork, .canada, .europeanUnion]
        let usStateIndex = loadUSStateIndex(matching: Set(usStateNames.values))

        var entries: [RegionPolygons] = []
        for region in regions {
            if let stateName = usStateNames[region] {
                if let polygons = usStateIndex[stateName] {
                    entries.append(RegionPolygons(region: region, polygons: polygons))
                } else {
                    // Either the bundle resource is missing entirely (caught
                    // upstream and logged) or the named feature isn't in the
                    // file. Either way, this region would silently attribute
                    // to `.other`; surface it via fault + assertionFailure.
                    logger
                        .fault(
                            "Missing feature \(stateName) in bundled us-states.geojson for region \(region.rawValue)",
                        )
                    assertionFailure(
                        "Missing feature \(stateName) in us-states.geojson for region \(region.rawValue)",
                    )
                }
                continue
            }

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
                assertionFailure("Failed to decode bundled GeoJSON \(region.rawValue): \(error)")
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
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(GeoJSON.FeatureCollection.self, from: data)
            var index: [String: [GeoPolygon]] = [:]
            for feature in decoded.features {
                guard let name = feature.properties?.name, wanted.contains(name) else { continue }
                index[name, default: []]
                    .append(contentsOf: GeoJSON.polygons(from: feature.geometry))
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
