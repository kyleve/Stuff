import Foundation

/// Thin `Decodable` views over the slice of the GeoJSON 1.0 spec that
/// `WhereCore` actually consumes: a `FeatureCollection` of `Feature`s
/// whose geometry is a `Polygon` or `MultiPolygon`. Anything else in
/// the spec (`Point`, `LineString`, foreign members, etc.) is ignored
/// at decode time.
///
/// Kept separate from `RegionAttributor` so the attributor can stay
/// focused on "coordinate -> Region" — it consumes GeoJSON, but GeoJSON
/// itself is its own thing and could be lifted into a shared module
/// later without dragging the attributor along.
enum GeoJSON {
    /// Top-level GeoJSON document we load from `Resources/*.geojson`.
    struct FeatureCollection: Decodable {
        let type: String
        let features: [Feature]
    }

    /// A single feature: geometry plus optional properties (we only
    /// read `NAME` out of the properties bag, for US state lookup).
    struct Feature: Decodable {
        let type: String
        let geometry: Geometry
        let properties: Properties?
    }

    /// Decoded properties bag. The US Census GeoJSON uses uppercase
    /// `NAME`; we project just that field so the rest of the bag is
    /// ignored at decode time.
    struct Properties: Decodable {
        let name: String?

        private enum CodingKeys: String, CodingKey {
            case name = "NAME"
        }
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

    /// Load every polygon (exterior ring only — holes aren't modeled)
    /// from a bundled GeoJSON file at `url`.
    static func polygons(at url: URL) throws -> [GeoPolygon] {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(FeatureCollection.self, from: data)
        return decoded.features.flatMap { polygons(from: $0.geometry) }
    }

    /// Project a `Geometry` to a list of `GeoPolygon` exterior rings.
    /// Holes (interior rings) are intentionally dropped; the bundled
    /// simplified region polygons don't model them.
    static func polygons(from geometry: Geometry) -> [GeoPolygon] {
        switch geometry {
            case let .polygon(rings):
                rings.first.map { [makePolygon(from: $0)] } ?? []
            case let .multiPolygon(polys):
                polys.compactMap { polyRings in
                    polyRings.first.map { makePolygon(from: $0) }
                }
        }
    }

    /// Convert a single ring (`[[longitude, latitude, ...]]`) into a
    /// `GeoPolygon`. Coordinate pairs with fewer than 2 components
    /// trigger an `assertionFailure` (malformed bundled file in debug)
    /// and are dropped.
    static func makePolygon(from ring: [[Double]]) -> GeoPolygon {
        let vertices = ring.compactMap { pair -> Coordinate? in
            // GeoJSON spec mandates `[longitude, latitude]` (and an
            // optional altitude as the third entry). Anything shorter
            // is a malformed bundled file — surface it in debug
            // builds while still returning nil so the rest of the
            // load can proceed.
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
}
