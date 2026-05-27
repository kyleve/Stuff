import Foundation
import os

/// Maps coordinates to the tracked `Region` they fall inside. Backed by a
/// list of polygons per region; checked in declaration order so the first
/// match wins (regions are mutually exclusive at our resolution).
///
/// Polygons are loaded from bundled GeoJSON in `Resources/`:
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

    public static let bundled: RegionAttributor = .loadFromBundle()

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

    private static let logger = Logger(subsystem: "com.stuff.where", category: "RegionAttributor")

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
                            "Missing feature \(stateName, privacy: .public) in bundled us-states.geojson for region \(region.rawValue, privacy: .public)",
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
                        "Missing required bundled GeoJSON for region \(region.rawValue, privacy: .public)",
                    )
                assertionFailure("Missing bundled GeoJSON for region \(region.rawValue)")
                continue
            }
            do {
                let polygons = try loadGeoJSONPolygons(at: url)
                entries.append(RegionPolygons(region: region, polygons: polygons))
            } catch {
                logger
                    .fault(
                        "Failed to decode bundled GeoJSON \(region.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)",
                    )
                assertionFailure("Failed to decode bundled GeoJSON \(region.rawValue): \(error)")
            }
        }
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
            let decoded = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: data)
            var index: [String: [GeoPolygon]] = [:]
            for feature in decoded.features {
                guard let name = feature.properties?.name, wanted.contains(name) else { continue }
                index[name, default: []].append(contentsOf: polygons(from: feature.geometry))
            }
            return index
        } catch {
            logger
                .fault(
                    "Failed to decode bundled us-states.geojson: \(error.localizedDescription, privacy: .public)",
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
        // Empty polygon set ⇒ degenerate bbox that never contains
        // anything. The loader assertion-failures earlier in the
        // pipeline already cover the "missing polygons" case, so this
        // is only the no-op fallback for a truly empty value.
        boundingBox = BoundingBox.enclosing(polygons) ?? BoundingBox(
            minLatitude: .infinity,
            maxLatitude: -.infinity,
            minLongitude: .infinity,
            maxLongitude: -.infinity,
        )
    }
}

private func loadGeoJSONPolygons(at url: URL) throws -> [GeoPolygon] {
    let data = try Data(contentsOf: url)
    let decoded = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: data)
    return decoded.features.flatMap { polygons(from: $0.geometry) }
}

private func polygons(from geometry: GeoJSONGeometry) -> [GeoPolygon] {
    switch geometry {
        case let .polygon(rings):
            rings.first.map { [makePolygon(from: $0)] } ?? []
        case let .multiPolygon(polys):
            polys.compactMap { polyRings in
                polyRings.first.map { makePolygon(from: $0) }
            }
    }
}

private func makePolygon(from ring: [[Double]]) -> GeoPolygon {
    let vertices = ring.compactMap { pair -> Coordinate? in
        // GeoJSON spec mandates `[longitude, latitude]` (and an
        // optional altitude as the third entry). Anything shorter is
        // a malformed bundled file — surface it in debug builds while
        // still returning nil so the rest of the load can proceed.
        guard pair.count >= 2 else {
            assertionFailure(
                "GeoJSON coordinate pair must have at least 2 components, got \(pair.count)",
            )
            return nil
        }
        return Coordinate(latitude: pair[1], longitude: pair[0])
    }
    return GeoPolygon(vertices: vertices)
}

// MARK: - GeoJSON decoder helpers

//
// Thin `Decodable` views over the slice of the GeoJSON 1.0 spec we
// actually consume: a `FeatureCollection` of `Feature`s whose geometry
// is a `Polygon` or `MultiPolygon`. Anything else in the spec
// (`Point`, `LineString`, foreign members, etc.) is ignored.

/// Top-level GeoJSON document we load from `Resources/*.geojson`.
private struct GeoJSONFeatureCollection: Decodable {
    let type: String
    let features: [GeoJSONFeature]
}

/// A single feature: geometry plus optional properties (we only read
/// `NAME` out of the properties bag, for US state lookup).
private struct GeoJSONFeature: Decodable {
    let type: String
    let geometry: GeoJSONGeometry
    let properties: GeoJSONProperties?
}

/// Decoded properties bag. The US Census GeoJSON uses uppercase
/// `NAME`; we project just that field so the rest of the bag is
/// ignored at decode time.
private struct GeoJSONProperties: Decodable {
    let name: String?

    private enum CodingKeys: String, CodingKey {
        case name = "NAME"
    }
}

/// The two geometry types we accept. `Polygon` is a list of rings
/// (exterior + optional holes); `MultiPolygon` is a list of those.
/// Anything else is decoded as a `dataCorruptedError` so unknown
/// shapes fail loudly rather than silently producing zero polygons.
private enum GeoJSONGeometry: Decodable {
    case polygon([[[Double]]])
    case multiPolygon([[[[Double]]]])

    private enum CodingKeys: String, CodingKey {
        case type
        case coordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
            case "Polygon":
                self = try .polygon(container.decode([[[Double]]].self, forKey: .coordinates))
            case "MultiPolygon":
                self = try .multiPolygon(container.decode(
                    [[[[Double]]]].self,
                    forKey: .coordinates,
                ))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unsupported geometry type: \(type)",
                )
        }
    }
}
