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
    private let regionPolygons: [(region: Region, polygons: [GeoPolygon])]

    public static let bundled: RegionAttributor = .loadFromBundle()

    init(regionPolygons: [(region: Region, polygons: [GeoPolygon])]) {
        self.regionPolygons = regionPolygons
    }

    public func region(at coordinate: Coordinate) -> Region {
        for entry in regionPolygons {
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
    /// The value is the GeoJSON feature's `properties.NAME`.
    private static let usStateNames: [Region: String] = [
        .california: "California",
        .newYork: "New York",
    ]

    private static func loadFromBundle() -> RegionAttributor {
        let regions: [Region] = [.california, .newYork, .canada, .europeanUnion]
        let usStateIndex = loadUSStateIndex(matching: Set(usStateNames.values))

        var entries: [(region: Region, polygons: [GeoPolygon])] = []
        for region in regions {
            if let stateName = usStateNames[region] {
                if let polygons = usStateIndex[stateName] {
                    entries.append((region, polygons))
                } else {
                    // Either the bundle resource is missing entirely (caught
                    // upstream and logged) or the named feature isn't in the
                    // file. Either way, this region would silently attribute
                    // to `.other`; surface it via fault + assertionFailure.
                    logger
                        .fault(
                            "Missing feature \(stateName, privacy: .public) in bundled us-states.geojson for region \(region.rawValue, privacy: .public)",
                        )
                    assertionFailure("Missing feature \(stateName) in us-states.geojson for region \(region.rawValue)")
                }
                continue
            }

            guard let url = Bundle.module.url(forResource: region.rawValue, withExtension: "geojson") else {
                logger.fault("Missing required bundled GeoJSON for region \(region.rawValue, privacy: .public)")
                assertionFailure("Missing bundled GeoJSON for region \(region.rawValue)")
                continue
            }
            do {
                let polygons = try loadGeoJSONPolygons(at: url)
                entries.append((region, polygons))
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
            logger.fault("Failed to decode bundled us-states.geojson: \(error.localizedDescription, privacy: .public)")
            assertionFailure("Failed to decode bundled us-states.geojson: \(error)")
            return [:]
        }
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
        guard pair.count >= 2 else { return nil }
        return Coordinate(latitude: pair[1], longitude: pair[0])
    }
    return GeoPolygon(vertices: vertices)
}

private struct GeoJSONFeatureCollection: Decodable {
    let type: String
    let features: [GeoJSONFeature]
}

private struct GeoJSONFeature: Decodable {
    let type: String
    let geometry: GeoJSONGeometry
    let properties: GeoJSONProperties?
}

private struct GeoJSONProperties: Decodable {
    let name: String?

    private enum CodingKeys: String, CodingKey {
        case name = "NAME"
    }
}

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
                self = try .multiPolygon(container.decode([[[[Double]]]].self, forKey: .coordinates))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unsupported geometry type: \(type)",
                )
        }
    }
}
