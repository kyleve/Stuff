import Foundation

/// Maps coordinates to the tracked `Region` they fall inside. Backed by a
/// list of polygons per region; checked in declaration order so the first
/// match wins (regions are mutually exclusive at our resolution).
///
/// Polygons are loaded from bundled simplified GeoJSON in `Resources/`.
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

    private static func loadFromBundle() -> RegionAttributor {
        let regions: [Region] = [.california, .newYork, .canada, .europeanUnion]
        var entries: [(region: Region, polygons: [GeoPolygon])] = []
        for region in regions {
            guard let url = Bundle.module.url(forResource: region.rawValue, withExtension: "geojson") else {
                continue
            }
            do {
                let polygons = try loadGeoJSONPolygons(at: url)
                entries.append((region, polygons))
            } catch {
                assertionFailure("Failed to decode bundled GeoJSON \(region.rawValue): \(error)")
            }
        }
        return RegionAttributor(regionPolygons: entries)
    }
}

private func loadGeoJSONPolygons(at url: URL) throws -> [GeoPolygon] {
    let data = try Data(contentsOf: url)
    let decoded = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: data)
    var polygons: [GeoPolygon] = []
    for feature in decoded.features {
        switch feature.geometry {
            case let .polygon(rings):
                if let exterior = rings.first {
                    polygons.append(makePolygon(from: exterior))
                }
            case let .multiPolygon(polys):
                for polyRings in polys {
                    if let exterior = polyRings.first {
                        polygons.append(makePolygon(from: exterior))
                    }
                }
        }
    }
    return polygons
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
