import Foundation
import PeriscopeCore

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

/// Failure decoding bundled region geometry. Surfaced (never swallowed) so
/// developer tools can show a real error state and production artwork can log
/// a broken bundled-resource invariant instead of silently drawing nothing.
public enum RegionGeometryError: Error {
    case missingResource(String)
    case emptyResource(String)
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
            case let .emptyResource(resource):
                "Bundled region geometry resource “\(resource).geojson” contains no drawable outlines."
        }
    }
}

/// Read-only catalog of region boundary geometry for region artwork and the
/// developer region-map viewer. UI never touches `RegionAttributor`'s internal
/// polygons or the `GeoJSON` decoder directly.
public enum RegionGeometryCatalog {
    /// Drawable outlines for one region, cached after the first request.
    ///
    /// This is the lightweight path for region-specific UI artwork: it decodes
    /// only `region` rather than the full source catalog. `.other` returns an
    /// empty array because it intentionally has no geometry. Missing, corrupt,
    /// or empty bundled geometry logs a fault and asserts in debug; release
    /// builds safely omit the decorative outline.
    public static func outlines(for region: Region) async -> [RegionOutline] {
        guard region != .other else { return [] }
        do {
            return try await RegionCache.shared.outlines(for: region)
        } catch {
            RegionLog.geometryCatalog(attachments: [.error(error, name: "geometry-error")]) {
                .regionLoadFailed(region: region, description: error.localizedDescription)
            }
            assertionFailure(
                "Failed to load drawable outlines for \(region.rawValue): \(error.localizedDescription)",
            )
            return []
        }
    }

    /// Drawable outlines for `kind`.
    ///
    /// - `.attribution` reflects exactly what `attributor` loaded (the tracked
    ///   subset) — the caller passes the attributor rather than the catalog
    ///   reaching for a global, so the viewer shows the regions it cares about.
    /// - `.source` decodes every available region from the catalog and ignores
    ///   `attributor`.
    ///
    /// `.source` decoding runs on its cache actor. `.attribution` maps the
    /// caller-provided attributor on the caller's actor because it is already
    /// resolved in memory. Throws `RegionGeometryError` / a `DecodingError`
    /// rather than absorbing a missing or malformed bundle into an empty list.
    public static func outlines(
        for kind: RegionGeometryKind,
        attributor: RegionAttributor,
    ) async throws -> [RegionOutline] {
        switch kind {
            case .attribution:
                attributionOutlines(for: attributor)
            case .source:
                try await SourceCache.shared.outlines()
        }
    }

    // MARK: - Attribution

    /// Outlines for exactly what `attributor` loaded — cheap, since it reads the
    /// already-resolved polygons.
    private static func attributionOutlines(for attributor: RegionAttributor) -> [RegionOutline] {
        var builder = OutlineBuilder()
        for entry in attributor.loadedRegionPolygons {
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
        try RegionLog.geometryCatalog.measure(.buildSourceOutlines, budget: .seconds(2)) {
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
    }

    private static func namedPolygons(for region: Region) throws -> [GeoJSON.NamedPolygons] {
        guard let url = RegionCatalog.shared.geometryURL(for: region) else {
            throw RegionGeometryError.missingResource(region.rawValue)
        }
        return try GeoJSON.namedPolygons(at: url)
    }

    /// Decode one region for card/overlay artwork without loading unrelated
    /// catalog entries.
    private static func buildRegionOutlines(for region: Region) throws -> [RegionOutline] {
        try RegionLog.geometryCatalog.measure(.loadRegionOutlines(region), budget: .seconds(1)) {
            var builder = OutlineBuilder()
            for feature in try namedPolygons(for: region) {
                for polygon in feature.polygons {
                    builder.add(
                        title: region.localizedName,
                        region: region,
                        coordinates: polygon.vertices,
                    )
                }
            }
            guard !builder.outlines.isEmpty else {
                throw RegionGeometryError.emptyResource(region.rawValue)
            }
            return builder.outlines
        }
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

    /// Per-region cache for UI artwork. Actor isolation serializes simultaneous
    /// requests for the same first-use decode without introducing a global
    /// mutable registry in the UI layer.
    private actor RegionCache {
        static let shared = RegionCache()
        private var cached: [Region: [RegionOutline]] = [:]

        func outlines(for region: Region) throws -> [RegionOutline] {
            if let cached = cached[region] { return cached }
            let built = try RegionGeometryCatalog.buildRegionOutlines(for: region)
            cached[region] = built
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
