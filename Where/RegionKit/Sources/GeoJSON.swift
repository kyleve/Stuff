import Foundation

/// Reads the Polygon and MultiPolygon features in the original GeoJSON resources.
enum GeoJSON {
    /// Top-level GeoJSON document we load from `Resources/*.geojson`.
    struct FeatureCollection: Decodable {
        let type: String
        let features: [Feature]
    }

    struct Feature: Decodable {
        let geometry: Geometry
    }

    /// The two geometry types we accept. `Polygon` is a list of rings
    /// (exterior + optional holes); `MultiPolygon` is a list of those.
    /// Anything else throws `dataCorruptedError` so unknown shapes fail
    /// loudly rather than silently producing zero polygons.
    enum Geometry: Decodable {
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

    static func polygons(in data: Data) throws -> [GeoPolygon] {
        let collection = try JSONDecoder().decode(FeatureCollection.self, from: data)
        return collection.features.flatMap { polygons(from: $0.geometry) }
    }

    static func polygons(from geometry: Geometry) -> [GeoPolygon] {
        switch geometry {
            case let .polygon(rings): makePolygon(from: rings).map { [$0] } ?? []
            case let .multiPolygon(polygons): polygons.compactMap(makePolygon(from:))
        }
    }

    private static func makePolygon(from rings: [[[Double]]]) -> GeoPolygon? {
        guard let exterior = rings.first else { return nil }
        let vertices = coordinates(exterior)
        guard vertices.isValidPolygonRing else { return nil }
        return GeoPolygon(
            vertices: vertices,
            holes: rings.dropFirst().map(coordinates),
        )
    }

    private static func coordinates(_ ring: [[Double]]) -> [Coordinate] {
        ring.compactMap { pair in
            guard pair.count >= 2 else {
                assertionFailure("GeoJSON coordinate needs longitude and latitude")
                return nil
            }
            return Coordinate(latitude: pair[1], longitude: pair[0])
        }
    }
}
