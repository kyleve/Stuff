import Foundation

/// Which set of region polygons to vend, for the developer region-map
/// viewer's source toggle.
public enum RegionGeometryKind: String, CaseIterable, Sendable, Hashable {
    /// What a `RegionAttributor` actually loaded and uses to attribute
    /// coordinates — the app's tracked subset, exterior rings only.
    case attribution
    /// Every available region in the catalog, decoded straight from its bundled
    /// per-region GeoJSON at full authored fidelity — what attribution is built
    /// *from*, before the bounding-box pre-pass simplifications.
    case source
}

/// One drawable region boundary: a single exterior ring tagged with a
/// display title and, when known, the `Region` it belongs to. A
/// MultiPolygon feature expands into several `RegionOutline`s (one per
/// sub-polygon). Holes are not represented — consistent with what
/// `RegionAttributor` uses and with MapKit's `MapPolygon`.
public struct RegionOutline: Identifiable, Sendable, Hashable {
    /// Typed identity (never a raw `String`): the title plus a running
    /// index, unique across a single `outlines(for:)` result so SwiftUI
    /// `ForEach` stays stable even when one feature yields many rings or
    /// several features share a title.
    public struct ID: Hashable, Sendable {
        public let title: String
        public let index: Int
    }

    public let id: ID
    /// Human-readable label: a `Region.localizedName` (e.g. "California").
    public let title: String
    /// The tracked region this outline belongs to, or `nil` for a source
    /// feature not modeled as a `Region`.
    public let region: Region?
    /// The exterior ring, in order.
    public let coordinates: [Coordinate]

    /// Hash on identity alone. `id` is unique within an `outlines(for:)`
    /// result, so this avoids walking the (often thousands-of-points)
    /// coordinate ring on every `Set`/dictionary insertion. The
    /// synthesized `==` still compares every field, so value equality is
    /// unchanged and the `a == b ⇒ hash(a) == hash(b)` contract holds.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Failure decoding bundled region geometry. Surfaced (never swallowed)
/// so the viewer can show a real error state instead of an empty map.
public enum RegionGeometryError: Error {
    case missingResource(String)
}

extension RegionGeometryError: LocalizedError {
    /// A developer-facing message that names the missing file, rather than
    /// the generic "operation couldn't be completed" the viewer's error
    /// state would otherwise show. Not localized — this only ever appears
    /// in the DEBUG region-map tool.
    public var errorDescription: String? {
        switch self {
            case let .missingResource(resource):
                "Missing bundled region geometry resource “\(resource).geojson”."
        }
    }
}

/// Read-only catalog of region boundary geometry for the developer
/// region-map viewer. The single public entry point is
/// ``outlines(for:)``; UI never touches `RegionAttributor`'s internal
/// polygons or the `GeoJSON` decoder directly.
public enum RegionGeometryCatalog {
    /// Drawable outlines for `kind`.
    ///
    /// The file read + JSON decode runs **off the main thread**:
    /// `RegionGeometryCatalog` is a plain (non-`@MainActor`) type and
    /// this method is `nonisolated`, so `await`-ing it from a
    /// `@MainActor` view hops to the cooperative pool (and, for
    /// `.source`, the cache actor) to decode, then returns the
    /// `Sendable` result back to the main actor. Throws
    /// `RegionGeometryError` / a `DecodingError` rather than absorbing a
    /// missing or malformed bundle into an empty list.
    public static func outlines(for kind: RegionGeometryKind) async throws -> [RegionOutline] {
        switch kind {
            case .attribution:
                attributionOutlines()
            case .source:
                try await SourceCache.shared.outlines()
        }
    }

    // MARK: - Attribution

    /// Outlines for exactly what the shared `RegionAttributor` loaded — cheap,
    /// since it reads the already-resolved `RegionAttributor.shared`.
    private static func attributionOutlines() -> [RegionOutline] {
        var builder = OutlineBuilder()
        for entry in RegionAttributor.shared.loadedRegionPolygons {
            for polygon in entry.polygons {
                builder.add(
                    title: entry.region.localizedName,
                    region: entry.region,
                    coordinates: polygon.vertices,
                )
            }
        }
        return builder.outlines
    }

    // MARK: - Source

    /// Decode every available region's bundled per-region GeoJSON at full
    /// fidelity, each outline tagged with the `Region` it belongs to and titled
    /// by its `localizedName`.
    static func buildSourceOutlines() throws -> [RegionOutline] {
        var builder = OutlineBuilder()
        for entry in RegionCatalog.shared.entries {
            for feature in try namedPolygons(for: entry.region) {
                for polygon in feature.polygons {
                    builder.add(
                        title: entry.region.localizedName,
                        region: entry.region,
                        coordinates: polygon.vertices,
                    )
                }
            }
        }
        return builder.outlines
    }

    private static func namedPolygons(for region: Region) throws -> [GeoJSON.NamedPolygons] {
        guard let url = RegionCatalog.shared.geometryURL(for: region) else {
            throw RegionGeometryError.missingResource(region.rawValue)
        }
        return try GeoJSON.namedPolygons(at: url)
    }

    /// Caches the heavy `.source` decode (parsing every per-region file) so
    /// toggling back to source after the first load is instant. An `actor` both
    /// serializes the one-time build and runs it off the main thread.
    private actor SourceCache {
        static let shared = SourceCache()
        private var cached: [RegionOutline]?

        func outlines() throws -> [RegionOutline] {
            if let cached { return cached }
            let built = try RegionGeometryCatalog.buildSourceOutlines()
            cached = built
            return built
        }
    }
}

/// Accumulates `RegionOutline`s while assigning each a unique, stable
/// `ID`, and drops degenerate rings (fewer than 3 vertices can't be
/// drawn).
private struct OutlineBuilder {
    private(set) var outlines: [RegionOutline] = []
    private var nextIndex = 0

    mutating func add(title: String, region: Region?, coordinates: [Coordinate]) {
        guard coordinates.isValidPolygonRing else { return }
        outlines.append(RegionOutline(
            id: RegionOutline.ID(title: title, index: nextIndex),
            title: title,
            region: region,
            coordinates: coordinates,
        ))
        nextIndex += 1
    }
}

extension BoundingBox {
    /// The smallest box enclosing every coordinate of every outline, or
    /// `nil` when `outlines` is empty. Reuses the shared
    /// `enclosing(_:)` coordinate core so the region-map viewer frames
    /// its camera from the same math the attributor pre-pass uses.
    public static func enclosing(_ outlines: [RegionOutline]) -> BoundingBox? {
        enclosing(outlines.lazy.flatMap(\.coordinates))
    }
}
